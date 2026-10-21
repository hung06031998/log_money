import 'notifications/notification_worker.dart' as worker;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notification_log_api.dart';
import 'notification_filter_page.dart';
import 'saved_notification.dart';
import 'time_format.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const LogNotiApp());
}

class LogNotiApp extends StatelessWidget {
  const LogNotiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);
    return MaterialApp(
      title: 'Log thông báo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const NotificationLogPage(),
    );
  }
}

class NotificationLogPage extends StatefulWidget {
  const NotificationLogPage({super.key});

  @override
  State<NotificationLogPage> createState() => _NotificationLogPageState();
}

class _NotificationLogPageState extends State<NotificationLogPage>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<Map<dynamic, dynamic>>? _events;

  List<SavedNotification> _items = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _permissionGranted = false;
  bool _listenerConnected = false;
  bool _batteryIgnored = true;
  String _query = '';
  String _filter = 'all';
  int _request = 0;
  Timer? _reloadTimer;

  static const _pageSize = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _events = NotificationLogApi.events().listen(_onNativeEvent);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _reloadTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus(reload: true);
    }
  }

  Future<void> _bootstrap() async {
    await _refreshStatus(reload: true);
    await NotificationLogApi.requestRebind();
    await NotificationLogApi.requestPostNotifications();
  }

  Future<void> _refreshStatus({required bool reload}) async {
    final permission = await NotificationLogApi.isPermissionGranted();
    final connected = await NotificationLogApi.isListenerConnected();
    final battery = await NotificationLogApi.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _permissionGranted = permission;
      _listenerConnected = connected;
      _batteryIgnored = battery;
    });
    if (reload) {
      await NotificationLogApi.startAnalysisQueue();
      await _reload();
    }
  }

  void _onNativeEvent(Map<dynamic, dynamic> event) {
    final type = event['type'];
    if (type == 'status') {
      final connected = event['listenerConnected'] == true;
      setState(() => _listenerConnected = connected);
      if (connected) {
        _reload();
      }
      return;
    }
    if (type == 'notification' || type == 'filter' || type == 'analysis') {
      _reloadTimer?.cancel();
      _reloadTimer =
          Timer(const Duration(milliseconds: 250), () => _reload(silent: true));
    }
  }

  Future<void> _editFilter() async {
    Navigator.pop(context);
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const NotificationFilterPage()));
    if (!mounted || saved != true) return;
    await _reload();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      if (!silent) _loading = true;
      _loadingMore = false;
    });
    try {
      final items = await NotificationLogApi.getNotifications(
        query: _query.isEmpty ? null : _query,
        limit: silent && _items.length > _pageSize ? _items.length : _pageSize,
        offset: 0,
        filter: _filter,
      );
      final total = await NotificationLogApi.getCount(
        query: _query.isEmpty ? null : _query,
        filter: _filter,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _items = items;
        _total = total;
      });
    } catch (_) {
      if (mounted && request == _request) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Không tải được lịch sử. Hãy thử lại.')));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _items.length >= _total) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final more = await NotificationLogApi.getNotifications(
        query: _query.isEmpty ? null : _query,
        limit: _pageSize,
        offset: _items.length,
        filter: _filter,
      );
      if (!mounted || request != _request) return;
      setState(() => _items = [..._items, ...more]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không tải thêm được thông báo.')));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _showCreateNotificationDialog() async {
    await NotificationLogApi.requestPostNotifications();
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => const _CreateNotificationDialog(),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã tạo thông báo')),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xóa toàn bộ nhật ký?'),
          content: const Text(
            'Tất cả thông báo đã lưu trên máy sẽ bị xóa. Thao tác này không hoàn tác được.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await NotificationLogApi.deleteAll();
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
          child: SafeArea(
              child: ListView(children: [
        const DrawerHeader(
            child: Text('Log thông báo', style: TextStyle(fontSize: 24))),
        ListTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: const Text('Chỉnh sửa bộ lọc thông báo'),
            onTap: _editFilter),
      ]))),
      appBar: AppBar(
        title: const Text('Nhật ký thông báo'),
        actions: [
          IconButton(
            tooltip: 'Tạo thông báo',
            onPressed: _showCreateNotificationDialog,
            icon: const Icon(Icons.notification_add_outlined),
          ),
          IconButton(
            tooltip: 'Làm mới',
            onPressed: () => _refreshStatus(reload: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Xóa nhật ký',
            onPressed: _items.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBanner(
            permissionGranted: _permissionGranted,
            listenerConnected: _listenerConnected,
            batteryIgnored: _batteryIgnored,
            onGrantPermission: () async {
              await NotificationLogApi.openPermissionSettings();
            },
            onRebind: () async {
              await NotificationLogApi.requestRebind();
              await _refreshStatus(reload: true);
            },
            onBattery: () async {
              await NotificationLogApi.requestIgnoreBatteryOptimizations();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Tìm theo ứng dụng, tiêu đề, nội dung',
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {}),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                      _reload();
                    },
                    icon: const Icon(Icons.close),
                  ),
              ],
              onSubmitted: (value) {
                setState(() => _query = value.trim());
                _reload();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonFormField<String>(
              value: _filter,
              decoration: const InputDecoration(
                  labelText: 'Hiển thị thông báo',
                  border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                DropdownMenuItem(
                    value: 'matched', child: Text('Biến động số dư')),
                DropdownMenuItem(value: 'unmatched', child: Text('Khác')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _filter = value);
                _reload();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$_total thông báo${_filter == 'all' ? ' đã lưu' : ' theo bộ lọc'}'
                '${_items.length < _total ? ' · đang hiện ${_items.length}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _refreshStatus(reload: true),
                    child: _items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              Icon(
                                Icons.notifications_none,
                                size: 64,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  _filter != 'all' || _query.isNotEmpty
                                      ? 'Không có thông báo phù hợp.'
                                      : 'Chưa có thông báo nào được lưu.\nHãy cấp quyền lắng nghe rồi để máy nhận thông báo.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _items.length + (_loadingMore ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              if (index >= _items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final item = _items[index];
                              return _NotificationTile(
                                item: item,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          NotificationDetailPage(item: item),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreateNotificationDialog extends StatefulWidget {
  const _CreateNotificationDialog();

  @override
  State<_CreateNotificationDialog> createState() =>
      _CreateNotificationDialogState();
}

class _CreateNotificationDialogState extends State<_CreateNotificationDialog> {
  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  final _bigTextController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    _bigTextController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final text = _textController.text.trim();
    final bigText = _bigTextController.text.trim();
    if (title.isEmpty && text.isEmpty) {
      setState(() => _error = 'Nhập tiêu đề hoặc nội dung thông báo.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await NotificationLogApi.postNotification(
      title: title,
      text: text,
      bigText: bigText.isEmpty ? null : bigText,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _submitting = false;
      _error =
          'Không gửi được thông báo. Hãy cho phép app hiển thị thông báo rồi thử lại.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo thông báo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề',
                hintText: 'Ví dụ: Nhắc việc',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              textInputAction: TextInputAction.next,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Nội dung',
                hintText: 'Nội dung ngắn hiện trên thanh thông báo',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bigTextController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Nội dung mở rộng (tuỳ chọn)',
                hintText: 'Hiện khi kéo thông báo ra',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('OK'),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.permissionGranted,
    required this.listenerConnected,
    required this.batteryIgnored,
    required this.onGrantPermission,
    required this.onRebind,
    required this.onBattery,
  });

  final bool permissionGranted;
  final bool listenerConnected;
  final bool batteryIgnored;
  final VoidCallback onGrantPermission;
  final VoidCallback onRebind;
  final VoidCallback onBattery;

  @override
  Widget build(BuildContext context) {
    if (!permissionGranted) {
      return _banner(
        context,
        color: Theme.of(context).colorScheme.errorContainer,
        icon: Icons.warning_amber_rounded,
        title: 'Chưa cấp quyền truy cập thông báo',
        body:
            'Bật quyền cho app này trong cài đặt hệ thống. Không cấp quyền thì không thể lưu thông báo.',
        actionLabel: 'Cấp quyền',
        onAction: onGrantPermission,
      );
    }
    if (!listenerConnected) {
      return _banner(
        context,
        color: Theme.of(context).colorScheme.tertiaryContainer,
        icon: Icons.sync_problem,
        title: 'Dịch vụ chưa kết nối',
        body:
            'Quyền đã có nhưng listener chưa chạy. Bấm kết nối lại, hoặc tắt/bật quyền nếu máy vừa khởi động.',
        actionLabel: 'Kết nối lại',
        onAction: onRebind,
      );
    }
    if (!batteryIgnored) {
      return _banner(
        context,
        color: Theme.of(context).colorScheme.secondaryContainer,
        icon: Icons.battery_alert,
        title: 'Nên tắt tối ưu pin',
        body:
            'Một số máy Android sẽ dừng app nền. Cho phép bỏ tối ưu pin để không bỏ sót thông báo.',
        actionLabel: 'Cho phép',
        onAction: onBattery,
      );
    }
    return Material(
      color: const Color(0xFFD1FAE5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF047857)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Đang lắng nghe. Thông báo mới sẽ được lưu ngay cả khi bạn thoát app.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF064E3B),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final SavedNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final letter =
        item.appName.isNotEmpty ? item.appName[0].toUpperCase() : '?';
    return ListTile(
      onTap: onTap,
      isThreeLine: true,
      leading: CircleAvatar(child: Text(letter)),
      title: Text(
        item.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.filterLabel}\n${item.displayBody}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${item.appName} · ${formatDateTime(item.receivedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class NotificationDetailPage extends StatefulWidget {
  const NotificationDetailPage({super.key, required this.item});

  final SavedNotification item;

  @override
  State<NotificationDetailPage> createState() => _NotificationDetailPageState();
}

class _NotificationDetailPageState extends State<NotificationDetailPage> {
  late SavedNotification item;
  StreamSubscription<Map<dynamic, dynamic>>? _analysisEvents;
  int _revision = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    item = widget.item;
    _analysisEvents = NotificationLogApi.events().listen((event) {
      final row = event['notification'];
      if (event['type'] == 'analysis' &&
          row is Map &&
          row['id'] == item.id &&
          mounted) {
        _revision++;
        setState(() => item = SavedNotification.fromMap(row));
      }
    });
    _refreshAnalysis();
  }

  Future<void> _refreshAnalysis() async {
    final revision = _revision;
    try {
      final updated = await NotificationLogApi.getNotification(item.id);
      if (mounted && revision == _revision) setState(() => item = updated);
    } catch (_) {
      // Keep the displayed notification if it was deleted meanwhile.
    }
  }

  @override
  void dispose() {
    _analysisEvents?.cancel();
    super.dispose();
  }

  Future<void> _analyze({bool force = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final updated =
          await NotificationLogApi.analyzeNotification(item.id, force: force);
      if (mounted) setState(() => item = updated);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Không tải được phân tích.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không tải được phân tích.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysis = item.analysis;
    final direction = switch (analysis?['direction']) {
      'increase' => 'Tăng',
      'decrease' => 'Giảm',
      _ => 'Không xác định',
    };
    final rows = <(String, String)>[
      ('Phân loại', item.filterLabel),
      if (_loading || item.analysisStatus == 'running')
        ('Gemini', 'Đang phân tích thông báo…'),
      if (!_loading && item.analysisStatus == 'queued')
        ('Gemini', 'Đang chờ phân tích…'),
      if (!_loading &&
          item.analysisStatus != 'running' &&
          (_error != null || item.analysisError != null))
        ('Gemini', _error ?? item.analysisError!),
      if (analysis != null) ...[
        ('Biến động (Gemini)', direction),
        (
          'Số tiền (Gemini)',
          '${analysis['amount'] == '' ? 'Không xác định' : analysis['amount']} ${analysis['currency']}'
        ),
        ('Nội dung giao dịch (Gemini)', analysis['description'] as String),
      ],
      ('Ứng dụng', item.appName),
      ('Gói ứng dụng', item.packageName),
      ('Tiêu đề', item.title),
      ('Nội dung', item.text),
      ('Nội dung mở rộng', item.bigText ?? ''),
      ('Tin nhắn', item.messages ?? ''),
      ('Phụ đề', item.subText ?? ''),
      ('Tóm tắt', item.summaryText ?? ''),
      ('Thông tin thêm', item.infoText ?? ''),
      ('Cuộc hội thoại', item.conversationTitle ?? ''),
      ('Kênh', item.channelId ?? ''),
      ('Phân loại', item.category ?? ''),
      ('Thời điểm đăng', formatDateTime(item.postTime)),
      ('Thời điểm lưu', formatDateTime(item.receivedAt)),
      ('Ongoing', item.isOngoing ? 'Có' : 'Không'),
      ('Group summary', item.isGroupSummary ? 'Có' : 'Không'),
      ('Key', item.notificationKey ?? ''),
      ('Tag', item.tag ?? ''),
      ('Notification ID', '${item.notificationId ?? ''}'),
      ('Op package', item.opPackage ?? ''),
      ('Extras', item.extrasJson ?? ''),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết thông báo'),
        actions: [
          TextButton.icon(
            onPressed: _loading || item.analysisStatus == 'running'
                ? null
                : () => _analyze(force: true),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Phân tích'),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row.$2.trim().isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.$1,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 4),
              SelectableText(row.$2),
            ],
          );
        },
      ),
    );
  }
}

// Native service starts this entry point without creating a Flutter UI.
@pragma('vm:entry-point')
void notificationWorkerMain() => worker.runNotificationWorker();
