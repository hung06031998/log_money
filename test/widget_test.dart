import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_noti_codex/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('notification_archive');
  var latest = 51;
  var fail = false;
  final requested = <int>[];
  final created = <Map>[];
  setUp(() {
    latest = 51;
    fail = false;
    requested.clear();
    created.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'createNotification') {
        if (fail) throw PlatformException(code: 'PERMISSION', message: 'Chưa cấp quyền');
        created.add(call.arguments as Map);
        return null;
      }
      if (call.method == 'status') {
        return {
          'enabled': true,
          'connected': true,
          'count': latest,
          'latest': latest
        };
      }
      if (call.method == 'page') {
        if (fail) {
          throw PlatformException(code: 'STORAGE', message: 'Disk error');
        }
        final args = call.arguments as Map;
        final before = args['before'] as int;
        requested.add(before);
        if (args['query'] == 'missing') return [];
        return [
          for (var i = before - 1; i > 0 && i >= before - 50; i--)
            {
              'id': i,
              'app': 'Ứng dụng',
              'package': 'test.app',
              'title': 'Thông báo $i',
              'body': 'Nội dung $i',
              'posted': 1000,
              'received': 1000,
              'source': 'posted'
            }
        ];
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  testWidgets(
      'Shows connection and records; pagination retains cursor when new data arrives',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Đang kết nối với Android'), findsOneWidget);
    expect(find.text('Thông báo 51'), findsOneWidget);
    latest = 52;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tải thêm thông báo'), 600,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Tải thêm thông báo'));
    await tester.pumpAndSettle();
    expect(requested, [52, 2]);
    await tester.scrollUntilVisible(find.text('Thông báo 1'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Thông báo 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Search distinguishes no matches from storage errors',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy kết quả.'), findsOneWidget);
    fail = true;
    await tester.enterText(find.byType(TextField), 'test');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không tải được lịch sử'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Create validates input and sends notification content', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tạo thông báo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(created, isEmpty);
    expect(find.text('Vui lòng nhập tiêu đề'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), ' Tiêu đề mới ');
    await tester.enterText(find.byType(TextFormField).at(1), ' Nội dung mới ');
    fail = true;
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa cấp quyền'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    fail = false;
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(created, [{'title': 'Tiêu đề mới', 'body': 'Nội dung mới'}]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Đã tạo thông báo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Cancel does not create a notification', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tạo thông báo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(created, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

}
