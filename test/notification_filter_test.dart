import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:log_noti/main.dart';
import 'package:log_noti/notification_filter_page.dart';
import 'package:log_noti/saved_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.example.log_noti/methods');
  const events = EventChannel('com.example.log_noti/events');
  final calls = <MethodCall>[];
  var settings = <String, dynamic>{};
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    settings = {
      'includes': 'nhận tiền',
      'excludes': 'phí dịch vụ',
      'apiKey': 'test-key',
      'model': 'gemini-3.8-flash'
    };
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'analyzeNotification':
          return {
            'id': 1,
            'analysisAttempted': true,
            'analysisJson':
                '{"direction":"increase","amount":"500000","currency":"VND","description":"Thanh toan don hang"}'
          };
        case 'getFilterSettings':
          return settings;
        case 'saveFilterSettings':
          settings = Map<String, dynamic>.from(call.arguments as Map);
          return true;
        case 'getFilterStatus':
          return {'enabled': true, 'pending': 2, 'errors': 1};
        case 'getNotifications':
          return <Map<String, dynamic>>[];
        case 'getCount':
          return 0;
        default:
          return true;
      }
    });
    messenger.setMockStreamHandler(
        events, MockStreamHandler.inline(onListen: (_, __) {}));
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  testWidgets('drawer opens persisted filter and saves edited rule',
      (tester) async {
    await tester.pumpWidget(const LogNotiApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chỉnh sửa bộ lọc thông báo'));
    await tester.pumpAndSettle();
    expect(find.text('nhận tiền'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).at(0), 'Nhận tiền trên 500.000 đồng');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lưu bộ lọc'), 250,
        scrollable: find
            .descendant(
                of: find.byType(NotificationFilterPage),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lưu bộ lọc'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu bộ lọc'));
    await tester.pumpAndSettle();
    expect(settings['includes'], 'Nhận tiền trên 500.000 đồng');
    expect(find.text('Nhật ký thông báo'), findsOneWidget);
  });

  testWidgets('local filter can be saved without API key', (tester) async {
    settings['apiKey'] = '';
    await tester.pumpWidget(const MaterialApp(home: NotificationFilterPage()));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lưu bộ lọc'), 250,
        scrollable: find
            .descendant(
                of: find.byType(NotificationFilterPage),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lưu bộ lọc'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu bộ lọc'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'saveFilterSettings'), hasLength(1));
    expect(settings['excludes'], 'phí dịch vụ');
  });

  testWidgets('history sends each filter to rows and count', (tester) async {
    await tester.pumpWidget(const LogNotiApp());
    await tester.pumpAndSettle();
    for (final entry in {
      'Biến động số dư': 'matched',
      'Khác': 'unmatched',
      'Tất cả': 'all'
    }.entries) {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      for (final method in ['getNotifications', 'getCount']) {
        expect(
            (calls.lastWhere((c) => c.method == method).arguments
                as Map)['filter'],
            entry.value);
      }
    }
  });

  testWidgets(
      'detail only requests analysis on tap and displays extracted fields',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: NotificationDetailPage(
      item: SavedNotification.fromMap({'id': 1, 'filterMatch': true}),
    )));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'analyzeNotification'), isEmpty);
    await tester.tap(find.text('Phân tích'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'analyzeNotification'), hasLength(1));
    expect(find.text('Tăng'), findsOneWidget);
    expect(find.text('500000 VND'), findsOneWidget);
    expect(find.text('Thanh toan don hang'), findsOneWidget);
  });

  testWidgets('cached attempt does not request analysis again', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: NotificationDetailPage(
      item: SavedNotification.fromMap(
          {'id': 1, 'analysisAttempted': true, 'analysisError': 'HTTP 429'}),
    )));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'analyzeNotification'), isEmpty);
    expect(find.text('HTTP 429'), findsOneWidget);
    await tester.tap(find.text('Phân tích'));
    await tester.pumpAndSettle();
    final request = calls.singleWhere((c) => c.method == 'analyzeNotification');
    expect((request.arguments as Map)['force'], true);
    expect(find.text('HTTP 429'), findsNothing);
    expect(find.text('500000 VND'), findsOneWidget);
  });

  testWidgets('other notification only analyzes on tap and supports reanalysis',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: NotificationDetailPage(
      item: SavedNotification.fromMap({'id': 1, 'filterMatch': false}),
    )));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'analyzeNotification'), isEmpty);
    for (var count = 1; count <= 2; count++) {
      await tester.tap(find.text('Phân tích'));
      await tester.pumpAndSettle();
      final requests = calls.where((c) => c.method == 'analyzeNotification');
      expect(requests, hasLength(count));
      expect((requests.last.arguments as Map)['force'], true);
      expect(find.text('500000 VND'), findsOneWidget);
    }
  });

  test('pending and errors remain distinct from a negative classification', () {
    SavedNotification row(Map<String, dynamic> extra) =>
        SavedNotification.fromMap({'id': 1, ...extra});
    expect(row({}).filterMatch, isNull);
    expect(row({'filterMatch': false}).filterLabel, 'Khác');
    expect(row({'filterMatch': true}).filterLabel, 'Biến động số dư');
    final failed = row({'filterError': 'HTTP 429'});
    expect(failed.filterMatch, isNull);
    expect(failed.filterLabel, contains('HTTP 429'));
  });
}
