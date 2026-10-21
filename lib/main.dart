import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Nhật ký thông báo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff167968)),
          scaffoldBackgroundColor: const Color(0xfff5f7f8),
          useMaterial3: true,
        ),
        home: const ArchiveScreen(),
      );
}

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});
  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('notification_archive');
  final search = TextEditingController();
  final rows = <Map<String, dynamic>>[];
  Map<String, dynamic> status = {};
  Timer? poll;
  Timer? debounce;
  String? error;
  String query = '';
  bool loading = false;
  bool hasMore = true;
  int generation = 0;
  int snapshot = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    poll = Timer.periodic(const Duration(seconds: 3), (_) => readStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) readStatus();
  }

  Future<void> readStatus() async {
    try {
      final value = await channel.invokeMapMethod<String, dynamic>('status');
      if (mounted) setState(() => status = value ?? {});
    } catch (e) {
      if (mounted) setState(() => error = 'Không đọc được trạng thái: $e');
    }
  }

  Future<void> refresh() async {
    final token = ++generation;
    setState(() {
      rows.clear();
      loading = false;
      hasMore = true;
      error = null;
    });
    await readStatus();
    if (!mounted || token != generation) return;
    snapshot = (status['latest'] as num?)?.toInt() ?? 0;
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    final token = generation;
    setState(() => loading = true);
    try {
      final result = await channel.invokeListMethod<dynamic>('page', {
        'before': rows.isEmpty ? snapshot + 1 : rows.last['id'],
        'query': query,
      });
      if (!mounted || token != generation) return;
      final page =
          (result ?? []).map((e) => Map<String, dynamic>.from(e as Map));
      setState(() {
        rows.addAll(page);
        hasMore = page.length == 50;
        error = null;
      });
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => error = 'Không tải được lịch sử. Hãy thử lại.\n$e');
      }
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  Future<void> action(String method) async {
    try {
      await channel.invokeMethod<void>(method);
      await readStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thực hiện được: $e')),
        );
      }
    }
  }

  Future<void> createNotification() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateNotificationDialog(),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã tạo thông báo')),
    );
    await readStatus();
  }

  String time(dynamic value) {
    final d = DateTime.fromMillisecondsSinceEpoch((value as num).toInt());
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Future<void> detail(Map<String, dynamic> row) async {
    try {
      final payload =
          await channel.invokeMethod<String>('detail', {'id': row['id']});
      if (!mounted) return;
      if (payload == null) {
        throw StateError('Không tìm thấy bản ghi');
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
                appBar: AppBar(title: Text(row['app'] as String)),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectionArea(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row['title'] as String,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 16),
                      Text(row['body'] as String),
                      const Divider(height: 32),
                      Text(
                          'Ứng dụng: ${row['package']}\nID bản ghi: ${row['id']}\nĐăng: ${time(row['posted'])}\nLưu: ${time(row['received'])}\nNguồn: ${row['source'] == 'recovered' ? 'Khôi phục khi kết nối' : 'Sự kiện từ Android'}'),
                      const SizedBox(height: 24),
                      const Text('Dữ liệu chi tiết',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                          const JsonEncoder.withIndent('  ')
                              .convert(jsonDecode(payload)),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                    ],
                  )),
                ),
              )));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không mở được bản ghi: $e')));
      }
    }
  }

  void help() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SafeArea(
            child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Thiết lập nhận thông báo',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                const Text(
                    '1. Cho phép quyền truy cập thông báo. Ứng dụng sẽ đọc và lưu nội dung thông báo trên thiết bị, có thể bao gồm tin nhắn riêng tư.\n\n2. Trong cài đặt pin, chọn không hạn chế cho ứng dụng. Với một số hãng, cần bật tự khởi động.\n\n3. Không buộc dừng ứng dụng. Sau khi khởi động lại điện thoại, hãy mở khóa thiết bị.\n\nDữ liệu chỉ lưu trên thiết bị, không tự xóa lịch sử. Gỡ ứng dụng hoặc xóa dữ liệu sẽ mất lịch sử.\n\nAndroid có thể ngắt dịch vụ hoặc ẩn nội dung nhạy cảm/OTP. Thông báo đã biến mất trong thời gian mất kết nối không thể khôi phục. Ảnh, tệp đính kèm và giao diện tùy biến không được sao chép; màn hình chi tiết hiển thị nội dung văn bản và metadata Android cung cấp.'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  FilledButton(
                      onPressed: () => action('access'),
                      child: const Text('Cấp quyền')),
                  OutlinedButton(
                      onPressed: () => action('battery'),
                      child: const Text('Cài đặt pin')),
                  TextButton(
                      onPressed: () => action('settings'),
                      child: const Text('Thông tin ứng dụng')),
                ]),
              ]),
        )),
      );

  @override
  Widget build(BuildContext context) {
    final connected = status['connected'] == true && status['enabled'] == true;
    final newItems = ((status['latest'] as num?)?.toInt() ?? 0) > snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký thông báo'),
        actions: [
          IconButton(
              onPressed: createNotification,
              tooltip: 'Tạo thông báo',
              icon: const Icon(Icons.add_alert_outlined)),
          IconButton(
              onPressed: refresh,
              tooltip: 'Làm mới',
              icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: help,
              tooltip: 'Thiết lập',
              icon: const Icon(Icons.settings_outlined))
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: rows.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: connected
                          ? const Color(0xffe1f3ed)
                          : const Color(0xffffeed6),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(connected
                                      ? Icons.sensors
                                      : Icons.sensors_off),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(
                                          connected
                                              ? 'Đang kết nối với Android'
                                              : 'Chưa kết nối dịch vụ',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)))
                                ]),
                                const SizedBox(height: 8),
                                Text(
                                    '${status['count'] ?? 0} bản ghi đã lưu • Lưu trên thiết bị'),
                                if (!connected)
                                  Wrap(spacing: 8, children: [
                                    TextButton(
                                        onPressed: () => action('access'),
                                        child: const Text('Quyền thông báo')),
                                    TextButton(
                                        onPressed: () => action('reconnect'),
                                        child: const Text('Kết nối lại')),
                                  ]),
                                if (status['batteryExempt'] == false)
                                  TextButton(
                                      onPressed: () => action('battery'),
                                      child:
                                          const Text('Kiểm tra giới hạn pin')),
                              ])),
                    ),
                    if (status['error'] != null)
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                              'Đã xảy ra lỗi lưu/khôi phục, có thể thiếu dữ liệu. Lỗi gần nhất: ${status['error']}',
                              style: const TextStyle(color: Colors.red))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: search,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Tìm ứng dụng, tiêu đề, nội dung',
                            border: OutlineInputBorder()),
                        onChanged: (value) {
                          debounce?.cancel();
                          debounce =
                              Timer(const Duration(milliseconds: 350), () {
                            query = value.trim();
                            refresh();
                          });
                        }),
                    const SizedBox(height: 12),
                    if (newItems)
                      FilledButton.tonalIcon(
                          onPressed: refresh,
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('Có bản ghi mới • Nhấn để xem')),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('LỊCH SỬ • MỚI NHẤT TRƯỚC',
                            style: TextStyle(fontSize: 12, letterSpacing: 1))),
                  ]);
            }
            if (index == rows.length + 1) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(children: [
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (loading)
                    const CircularProgressIndicator()
                  else if (error != null)
                    TextButton(onPressed: refresh, child: const Text('Thử lại'))
                  else if (rows.isEmpty)
                    Text(
                        query.isEmpty
                            ? 'Chưa có thông báo được lưu.\nCấp quyền rồi nhận một thông báo mới.'
                            : 'Không tìm thấy kết quả.',
                        textAlign: TextAlign.center)
                  else if (hasMore)
                    OutlinedButton(
                        onPressed: loadMore,
                        child: const Text('Tải thêm thông báo'))
                  else
                    Text(
                        'Đã hiển thị tất cả ${rows.length} bản ghi${query.isEmpty ? '' : ' phù hợp'}.')
                ]),
              );
            }
            final row = rows[index - 1];
            return Card(
                child: InkWell(
                    onTap: () => detail(row),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${row['app']} • ${time(row['posted'])}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                            const SizedBox(height: 8),
                            Text(
                                (row['title'] as String).isEmpty
                                    ? '(Không có tiêu đề)'
                                    : row['title'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text((row['body'] as String).isEmpty
                                ? 'Mở chi tiết để xem dữ liệu Android cung cấp.'
                                : row['body'] as String),
                            if (row['source'] == 'recovered')
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                      'Khôi phục từ thông báo còn hoạt động',
                                      style: TextStyle(fontSize: 11))),
                          ]),
                    )));
          },
        ),
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
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final body = TextEditingController();
  bool sending = false;
  String? error;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (sending || !form.currentState!.validate()) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await _ArchiveScreenState.channel.invokeMethod<void>(
        'createNotification',
        {'title': title.text.trim(), 'body': body.text.trim()},
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Không tạo được thông báo.');
    } catch (_) {
      if (mounted) setState(() => error = 'Không tạo được thông báo trên thiết bị này.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !sending,
        child: AlertDialog(
          title: const Text('Tạo thông báo'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: title,
                    autofocus: true,
                    enabled: !sending,
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Tiêu đề'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Vui lòng nhập tiêu đề'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: body,
                    enabled: !sending,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'Nội dung'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Vui lòng nhập nội dung'
                        : null,
                  ),
                  if (error != null)
                    Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: sending ? null : submit,
              child: Text(sending ? 'Đang tạo…' : 'OK'),
            ),
          ],
        ),
      );
}
