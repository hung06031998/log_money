import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_noti/notifications/gemini_analyzer.dart';
import 'package:log_noti/notifications/notification_store.dart';
import 'package:log_noti/notifications/notification_worker.dart';

class FakeAnalyzer extends GeminiAnalyzer {
  int calls = 0;
  Completer<void>? pause;
  bool fail = false;
  @override
  Future<String> evaluate(Map<String, dynamic> row,
      {required String apiKey, required String model}) async {
    calls++;
    await pause?.future;
    if (fail) throw const AnalysisException('HTTP 429');
    return '{"direction":"increase","amount":"500000","currency":"VND","description":"test"}';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/worker');
  late Directory temp;
  late NotificationStore store;
  late NotificationWorker worker;
  late FakeAnalyzer analyzer;
  late Map<String, dynamic> config;
  final events = <Map>[];
  // Real SQLite, accessed through the same bound-statement contract as Android.
  // Python 3 is used only by host tests, never by the application.
  const sqlite = '''
import sqlite3, json, sys
connection = sqlite3.connect(sys.argv[1])
connection.row_factory = sqlite3.Row
request = json.loads(sys.argv[2])
if request['method'] == 'query':
    print(json.dumps([dict(row) for row in connection.execute(request['sql'], request['args'])]))
else:
    with connection:
        for statement in request['statements']:
            connection.execute(statement['sql'], statement.get('args', []))
    print('null')
connection.close()
''';
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('notification-test-');
    config = {
      'includes': '',
      'excludes': '',
      'apiKey': 'key',
      'model': 'test-model'
    };
    events.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readSettings':
          return Map<String, dynamic>.from(config);
        case 'writeSettings':
          config = Map<String, dynamic>.from(call.arguments as Map);
          return null;
        case 'emit':
          events.add(call.arguments as Map);
          return null;
        default:
          final result = await Process.run('python3', [
            '-c',
            sqlite,
            '${temp.path}/test.db',
            jsonEncode({'method': call.method, ...call.arguments as Map})
          ]);
          if (result.exitCode != 0) throw StateError(result.stderr as String);
          return jsonDecode(result.stdout as String);
      }
    });
    store = NotificationStore(channel);
    await store.execute(
        'CREATE TABLE native_inbox (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, snapshot INTEGER NOT NULL)');
    analyzer = FakeAnalyzer();
    worker = NotificationWorker(channel, analyzer: analyzer);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });
  Future<void> enqueue({String key = 'one', bool snapshot = false}) =>
      store.execute(
          'INSERT INTO native_inbox (payload, snapshot) VALUES (?, ?)', [
        jsonEncode({
          'packageName': 'bank',
          'title': 'Bank',
          'text': 'TK 123 +500000 VND',
          'notificationKey': key,
          'postTime': 100,
          'receivedAt': 100,
        }),
        snapshot ? 1 : 0
      ]);
  Future<dynamic> call(String method, [Map? args]) =>
      worker.handle(MethodCall(method, args));

  test('imports durable inbox, deduplicates, classifies and filters history',
      () async {
    await enqueue();
    await enqueue(snapshot: true);
    await enqueue();
    await call('drain');
    expect(await call('getCount', {'filter': 'matched'}), 1);
    expect(await call('getCount', {'query': 'missing'}), 0);
    expect(await store.query('SELECT * FROM native_inbox'), isEmpty);
    final rows = await call('getNotifications', {'filter': 'matched'}) as List;
    expect(rows.single['filterMatch'], true);
    expect(
        events.where((event) => event['type'] == 'notification'), hasLength(1));
    expect(analyzer.calls, 0);
  });
  test(
      'startup queues matches, manual analysis removes queued work and syncs status',
      () async {
    await enqueue(key: 'first');
    await enqueue(key: 'second');
    await enqueue(key: 'third');
    analyzer.pause = Completer<void>();
    await call('startAnalysisQueue');
    while (analyzer.calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect((await call('getNotification', {'id': 1}))['analysisStatus'],
        'running');
    expect(
        (await call('getNotification', {'id': 2}))['analysisStatus'], 'queued');
    // Opening details is read-only, even while HTTP is blocked.
    expect(analyzer.calls, 1);
    final manual = call('analyzeNotification', {'id': 2, 'force': true});
    while (analyzer.calls < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final duplicate = call('analyzeNotification', {'id': 2, 'force': true});
    expect((await call('getNotification', {'id': 2}))['analysisStatus'],
        'running');
    analyzer.pause!.complete();
    await Future.wait([manual, duplicate]);
    while (!events.any((event) =>
        event['type'] == 'analysis' &&
        event['notification']['id'] == 3 &&
        event['notification']['analysisStatus'] == 'idle' &&
        event['notification']['analysisJson'] != null)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await call('startAnalysisQueue');
    expect(analyzer.calls, 3);
    expect(
        (await call('getNotification', {'id': 2}))['analysisJson'], isNotNull);
  });

  test(
      'queue retries failures once per startup and preserves successful results',
      () async {
    await enqueue(key: 'failed');
    await enqueue(key: 'successful');
    await call('drain');
    analyzer.fail = true;
    await call('analyzeNotification', {'id': 1});
    analyzer.fail = false;
    await call('analyzeNotification', {'id': 2});
    analyzer.fail = true;
    await call('startAnalysisQueue');
    Future<void> waitForIdle() async {
      while ((await call('getNotification', {'id': 1}))['analysisStatus'] !=
          'idle') {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    await waitForIdle();
    expect(analyzer.calls, 3);
    await call('getNotifications');
    await call('drain');
    expect(analyzer.calls, 3);
    analyzer.fail = false;
    await call('startAnalysisQueue');
    await waitForIdle();
    expect(analyzer.calls, 4);
    expect((await store.getById(1))['analysisError'], isNull);
    expect((await store.getById(1))['analysisJson'], isNotNull);
    await call('startAnalysisQueue');
    expect(analyzer.calls, 4);
  });

  test('missing API key leaves notifications available for a later startup',
      () async {
    await enqueue();
    config['apiKey'] = '';
    await call('startAnalysisQueue');
    expect(analyzer.calls, 0);
    expect(
        (await call('getNotification', {'id': 1}))['analysisAttempted'], false);
  });

  test('migrates v1 history in place', () async {
    final sql = NotificationStore.schema.first;
    final legacyColumns = sql
        .substring(0, sql.indexOf('                filter_match'))
        .trimRight()
        .replaceFirst(RegExp(r',$'), '');
    final legacy = '$legacyColumns\n)';
    await store.execute(legacy);
    await store.execute('PRAGMA user_version = 1');
    await store.execute(
        "INSERT INTO notifications (package_name, title, text, post_time, received_at) VALUES ('old', 'Old', 'TK +100 VND', 1, 1)");
    await call('drain');
    expect(await call('getCount', {'filter': 'matched'}), 1);
    expect(
        (await store.query('PRAGMA user_version')).single['user_version'], 3);
  });
  test('settings reclassify history without clearing saved analysis', () async {
    await enqueue();
    await call('drain');
    await call('analyzeNotification', {'id': 1});
    await call('saveFilterSettings', {...config, 'excludes': 'TK'});
    final row = await store.getById(1);
    expect(row['filterMatch'], false);
    expect(row['analysisAttempted'], true);
    expect(row['analysisJson'], isNotNull);
    expect(analyzer.calls, 1);
  });
  test(
      'concurrent requests call once and failed analysis can retry after restart',
      () async {
    await enqueue();
    await call('drain');
    analyzer.fail = true;
    await Future.wait([
      call('analyzeNotification', {'id': 1}),
      call('analyzeNotification', {'id': 1})
    ]);
    expect(analyzer.calls, 1);
    worker = NotificationWorker(channel, analyzer: analyzer);
    expect((await call('analyzeNotification', {'id': 1}))['analysisError'],
        'HTTP 429');
    expect(analyzer.calls, 2);
    await call('analyzeNotification', {'id': 1, 'force': true});
    expect(analyzer.calls, 3);
  });
  test('in-flight HTTP does not block history or resurrect deleted rows',
      () async {
    await enqueue();
    await call('drain');
    analyzer.pause = Completer<void>();
    final analysis = call('analyzeNotification', {'id': 1});
    while (analyzer.calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await call('getCount'), 1);
    await call('deleteAll');
    final assertion = expectLater(analysis, throwsA(isA<PlatformException>()));
    analyzer.pause!.complete();
    await assertion;
    expect(await call('getCount'), 0);
  });
}
