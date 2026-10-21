import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:log_noti/main.dart';

void main() {
  const methods = MethodChannel('com.example.log_noti/methods');
  const events = EventChannel('com.example.log_noti/events');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      switch (call.method) {
        case 'isPermissionGranted':
          return false;
        case 'isListenerConnected':
          return false;
        case 'isIgnoringBatteryOptimizations':
          return true;
        case 'getNotifications':
          return <Map<String, dynamic>>[];
        case 'getCount':
          return 0;
        case 'requestRebind':
        case 'requestPostNotifications':
        case 'postNotification':
          return true;
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink sink) {},
      ),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(events, null);
  });

  testWidgets('shows notification log title and permission banner',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LogNotiApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Nhật ký thông báo'), findsOneWidget);
    expect(find.text('Chưa cấp quyền truy cập thông báo'), findsOneWidget);
  });

  testWidgets('opens create notification dialog from app bar',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LogNotiApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Tạo thông báo'));
    await tester.pumpAndSettle();

    expect(find.text('Tạo thông báo'), findsWidgets);
    expect(find.text('Tiêu đề'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });
}
