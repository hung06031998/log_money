import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'balance_classifier.dart';
import 'gemini_analyzer.dart';
import 'notification_store.dart';

/// One owner for background processing and UI requests, even with no Activity.
void runNotificationWorker() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.log_noti/worker');
  final worker = NotificationWorker(channel);
  channel.setMethodCallHandler(worker.handle);
  // The handler awaits initialization, so startup errors reach callers rather
  // than leaving native requests queued forever.
  unawaited(channel.invokeMethod<void>('ready'));
}

class NotificationWorker {
  NotificationWorker(this.channel, {GeminiAnalyzer? analyzer})
      : store = NotificationStore(channel),
        analyzer = analyzer ?? GeminiAnalyzer();

  final MethodChannel channel;
  final NotificationStore store;
  final GeminiAnalyzer analyzer;
  Future<void>? _initialization;
  Future<void> _queue = Future.value();
  final Set<int> _pending = {};
  // Failed requests are retried at most once per queue startup.
  final Set<int> _attemptedInQueue = {};
  final Map<int, Future<Map<String, dynamic>>> _running = {};
  bool _backgroundEnabled = false;
  bool _pumping = false;

  Map<String, dynamic> _withStatus(Map<String, dynamic> row) => {
        ...row,
        'analysisStatus': _running.containsKey(row['id'])
            ? 'running'
            : _pending.contains(row['id'])
                ? 'queued'
                : 'idle',
      };

  Future<void> _publish(int id) async {
    await emit({
      'type': 'analysis',
      'notification': _withStatus(await store.getById(id))
    });
  }

  Future<Map<String, dynamic>> _requestAnalysis(Map args) {
    final id = args['id'] as int;
    final existing = _running[id];
    if (existing != null) return existing;
    _pending.remove(id);
    _attemptedInQueue.add(id);
    final future = analyze(args);
    _running[id] = future;
    return future.whenComplete(() => _running.remove(id));
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_pending.isNotEmpty) {
        final id = _pending.first;
        try {
          await _requestAnalysis({'id': id});
        } catch (_) {
          // A deleted row or unavailable configuration must not stop the queue.
        }
        try {
          await _serial(() => _publish(id));
        } catch (_) {
          // The notification may have been deleted during HTTP.
        }
      }
    } finally {
      _pumping = false;
    }
  }

  static const defaultModel = 'gemini-3.8-flash';

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<Map<String, dynamic>> settings() async {
    final values =
        await channel.invokeMapMethod<String, dynamic>('readSettings') ?? {};
    return {...values, 'model': values['model'] ?? defaultModel};
  }

  Future<void> emit(Map<String, dynamic> event) =>
      channel.invokeMethod('emit', event);

  Future<dynamic> handle(MethodCall call) async {
    _initialization ??= store.initialize().catchError((Object error) {
      _initialization = null;
      throw error;
    });
    await _initialization;
    final args = call.arguments as Map? ?? const {};
    if (call.method == 'analyzeNotification') {
      final result = await _requestAnalysis(args);
      await _serial(() => _publish(args['id'] as int));
      return _withStatus(result);
    }
    return _serial(() async {
      switch (call.method) {
        case 'startAnalysisQueue':
          _backgroundEnabled = true;
          if (!_pumping) _attemptedInQueue.clear();
          await drain();
          return null;
        case 'getNotification':
          return _withStatus(await store.getById(args['id'] as int));
        case 'drain':
          await drain();
          return null;
        case 'getNotifications':
          await drain();
          return (await store.notifications(args)).map(_withStatus).toList();
        case 'getCount':
          await drain();
          return store.count(args);
        case 'getFilterSettings':
          return settings();
        case 'getFilterStatus':
          final counts = (await store.query(
                  'SELECT COALESCE(SUM(CASE WHEN filter_match IS NULL AND filter_error IS NULL THEN 1 ELSE 0 END), 0) AS pending, COALESCE(SUM(CASE WHEN filter_error IS NOT NULL THEN 1 ELSE 0 END), 0) AS errors FROM notifications'))
              .single;
          return {...counts, 'enabled': true};
        case 'saveFilterSettings':
          final model = (args['model'] as String? ?? '').trim();
          if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(model)) {
            throw PlatformException(
                code: 'filter_save', message: 'Nhập tên model Gemini hợp lệ.');
          }
          final old = await settings();
          final values = {
            'includes': args['includes'] as String? ?? '',
            'excludes': args['excludes'] as String? ?? '',
            'apiKey': args['apiKey'] as String? ?? '',
            'model': model,
          };
          // Reset first: interruption may cause extra local classification, but
          // can never leave old classifications attached to new settings.
          if (old['includes'] != values['includes'] ||
              old['excludes'] != values['excludes']) {
            await store.execute(
                'UPDATE notifications SET filter_match = NULL, filter_error = NULL');
          }
          await channel.invokeMethod('writeSettings', values);
          await drain();
          return null;
        case 'deleteAll':
          _pending.clear();
          _attemptedInQueue.clear();
          await store.transaction([
            {'sql': 'DELETE FROM notifications'},
            {'sql': 'DELETE FROM native_inbox'},
          ]);
          await emit({'type': 'filter'});
          return null;
        default:
          throw MissingPluginException(
              'Unknown notification operation: ${call.method}');
      }
    });
  }

  Future<void> drain() async {
    final config = await settings();
    var changed = false;
    while (true) {
      final inbox =
          await store.query('SELECT * FROM native_inbox ORDER BY id LIMIT 100');
      if (inbox.isEmpty) break;
      for (final item in inbox) {
        final row = await store.importInbox(item);
        if (row != null && item['snapshot'] == 0) {
          await emit({'type': 'notification', 'notification': row});
        }
      }
    }
    while (true) {
      final rows = await store.query(
          'SELECT * FROM notifications WHERE filter_match IS NULL AND filter_error IS NULL ORDER BY id DESC LIMIT 100');
      if (rows.isEmpty) break;
      await store.transaction(rows.map((raw) {
        final matches = BalanceClassifier.matches(
            NotificationStore.decodeRow(raw),
            includes: config['includes'] as String? ?? '',
            excludes: config['excludes'] as String? ?? '');
        return <String, dynamic>{
          'sql':
              'UPDATE notifications SET filter_match = ?, filter_error = NULL WHERE id = ?',
          'args': [matches ? 1 : 0, raw['id']]
        };
      }).toList());
      changed = true;
    }
    if (_backgroundEnabled) {
      final candidates = (config['apiKey'] as String? ?? '').trim().isEmpty
          ? <Map<String, dynamic>>[]
          : await store.query(
              'SELECT id FROM notifications WHERE filter_match = 1 AND (analysis_attempted = 0 OR analysis_error IS NOT NULL) ORDER BY received_at ASC, id ASC');
      final ids = candidates.map((row) => row['id'] as int).toSet();
      final previous = Set<int>.from(_pending);
      _pending.clear();
      _pending.addAll(ids.where((id) =>
          !_running.containsKey(id) && !_attemptedInQueue.contains(id)));
      for (final id in {...previous, ..._pending}) {
        if (previous.contains(id) != _pending.contains(id)) await _publish(id);
      }
      unawaited(_pump());
    }
    if (changed) await emit({'type': 'filter'});
  }

  Future<Map<String, dynamic>> analyze(Map args) async {
    final id = args['id'] as int;
    // Serialize claim + persisted attempt before HTTP. Network work does not
    // block capture, filtering, settings or history reads.
    final task = await _serial(() async {
      await drain();
      final row = await store.getById(id);
      if (args['force'] != true &&
          (row['filterMatch'] != true ||
              (row['analysisAttempted'] == true &&
                  row['analysisError'] == null))) {
        return (row: row, config: <String, dynamic>{}, run: false);
      }
      final config = await settings();
      if ((config['apiKey'] as String? ?? '').trim().isEmpty) {
        throw PlatformException(
            code: 'analysis',
            message: 'Nhập Gemini API key trong màn hình bộ lọc để phân tích.');
      }
      await store.saveAnalysis(
          id, null, 'Lần phân tích trước bị gián đoạn hoặc đang xử lý.');
      await _publish(id);
      return (row: row, config: config, run: true);
    });
    if (!task.run) return task.row;
    String? json;
    String? error;
    try {
      json = await analyzer.evaluate(task.row,
          apiKey: task.config['apiKey'] as String,
          model: task.config['model'] as String);
    } catch (e) {
      error = e is AnalysisException
          ? e.message
          : 'Không thể phân tích thông báo. Lỗi đã được lưu để thử lại khi khởi động hàng đợi.';
    }
    return _serial(() async {
      await store.saveAnalysis(id, json, error);
      return store.getById(id);
    });
  }
}
