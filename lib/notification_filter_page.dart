import 'package:flutter/material.dart';
import 'notification_log_api.dart';

class NotificationFilterPage extends StatefulWidget {
  const NotificationFilterPage({super.key});

  @override
  State<NotificationFilterPage> createState() => _NotificationFilterPageState();
}

class _NotificationFilterPageState extends State<NotificationFilterPage> {
  final _includes = TextEditingController();
  final _excludes = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController(text: 'gemini-3.8-flash');
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await NotificationLogApi.getFilterSettings();
      if (!mounted) return;
      _includes.text = settings['includes'] as String? ?? '';
      _excludes.text = settings['excludes'] as String? ?? '';
      _key.text = settings['apiKey'] as String? ?? '';
      _model.text = settings['model'] as String? ?? 'gemini-3.8-flash';
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Không tải được cấu hình. Hãy mở lại màn hình.');
      }
    }
  }

  Future<void> _save() async {
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(_model.text.trim())) {
      setState(() => _error = 'Nhập tên model Gemini hợp lệ.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await NotificationLogApi.saveFilterSettings(
        includes: _includes.text.trim(),
        excludes: _excludes.text.trim(),
        apiKey: _key.text.trim(),
        model: _model.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không lưu được bộ lọc. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _includes.dispose();
    _excludes.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Chỉnh sửa bộ lọc thông báo')),
        body: _loading && _error == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                const Text(
                    'Code tự nhận diện biến động số dư. Mỗi dòng là một cụm từ; không phân biệt hoa/thường và dấu tiếng Việt. Nếu nhập mục bao gồm, thông báo phải chứa ít nhất một dòng. Bất kỳ dòng loại trừ nào xuất hiện đều bị loại.'),
                const SizedBox(height: 16),
                TextField(
                    controller: _includes,
                    enabled: !_saving && !_loading,
                    minLines: 3,
                    maxLines: 12,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Bao gồm (mỗi dòng một cụm từ)',
                        hintText: 'Ví dụ: nhận tiền\nchuyển khoản')),
                const SizedBox(height: 16),
                TextField(
                    controller: _excludes,
                    enabled: !_saving && !_loading,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Không bao gồm (mỗi dòng một cụm từ)',
                        hintText: 'Ví dụ: thanh toán\nphí dịch vụ')),
                const SizedBox(height: 16),
                TextField(
                    controller: _key,
                    enabled: !_saving && !_loading,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Gemini API key')),
                const SizedBox(height: 16),
                TextField(
                    controller: _model,
                    enabled: !_saving && !_loading,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Model Gemini')),
                const SizedBox(height: 16),
                const Text(
                    'Bộ lọc hoạt động trên máy, không cần API key. Để trống các cụm từ để chỉ dùng nhận diện tự động. Gemini tự xếp hàng phân tích các thông báo biến động số dư khi mở ứng dụng. Với thông báo khác, hãy bấm Phân tích; có thể phát sinh phí API. Kết quả và lỗi được lưu trên máy. Các thông báo phân tích lỗi được thử lại khi khởi động hàng đợi, theo thứ tự nhận từ cũ đến mới. Bấm Phân tích trong chi tiết để gọi mới hoặc gọi lại Gemini.'),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: _saving || _loading ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Đang lưu…' : 'Lưu bộ lọc')),
              ]),
      );
}
