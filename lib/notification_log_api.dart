import 'package:flutter/services.dart';

import 'saved_notification.dart';

class NotificationLogApi {
  NotificationLogApi._();

  static const _methods = MethodChannel('com.example.log_noti/methods');
  static const _events = EventChannel('com.example.log_noti/events');

  static final Stream<Map<dynamic, dynamic>> _sharedEvents = _eventStream();

  static Stream<Map<dynamic, dynamic>> events() => _sharedEvents;

  static Stream<Map<dynamic, dynamic>> _eventStream() {
    return _events.receiveBroadcastStream().map((event) {
      return Map<dynamic, dynamic>.from(event as Map);
    });
  }

  static Future<bool> isPermissionGranted() async {
    return await _methods.invokeMethod<bool>('isPermissionGranted') ?? false;
  }

  static Future<void> openPermissionSettings() {
    return _methods.invokeMethod('openPermissionSettings');
  }

  static Future<bool> isListenerConnected() async {
    return await _methods.invokeMethod<bool>('isListenerConnected') ?? false;
  }

  static Future<void> requestRebind() {
    return _methods.invokeMethod('requestRebind');
  }

  static Future<List<SavedNotification>> getNotifications({
    String? query,
    int limit = 50,
    int offset = 0,
    String filter = 'all',
  }) async {
    final rows = await _methods.invokeMethod<List<dynamic>>(
      'getNotifications',
      <String, dynamic>{
        'query': query,
        'limit': limit,
        'offset': offset,
        'filter': filter,
      },
    );
    return (rows ?? const [])
        .map((row) => SavedNotification.fromMap(row as Map))
        .toList();
  }

  static Future<int> getCount({String? query, String filter = 'all'}) async {
    return await _methods.invokeMethod<int>('getCount', <String, dynamic>{
          'query': query,
          'filter': filter,
        }) ??
        0;
  }

  static Future<Map<dynamic, dynamic>> getFilterSettings() async =>
      await _methods.invokeMapMethod('getFilterSettings') ?? {};

  static Future<Map<dynamic, dynamic>> getFilterStatus() async =>
      await _methods.invokeMapMethod('getFilterStatus') ?? {};

  static Future<void> saveFilterSettings(
          {required String includes,
          required String excludes,
          required String apiKey,
          required String model}) =>
      _methods.invokeMethod('saveFilterSettings', {
        'includes': includes,
        'excludes': excludes,
        'apiKey': apiKey,
        'model': model
      });

  static Future<SavedNotification> analyzeNotification(int id,
      {bool force = false}) async {
    final row = await _methods
        .invokeMapMethod('analyzeNotification', {'id': id, 'force': force});
    return SavedNotification.fromMap(row!);
  }

  static Future<void> startAnalysisQueue() =>
      _methods.invokeMethod('startAnalysisQueue');

  static Future<SavedNotification> getNotification(int id) async =>
      SavedNotification.fromMap(
          (await _methods.invokeMapMethod('getNotification', {'id': id}))!);

  static Future<void> deleteAll() {
    return _methods.invokeMethod('deleteAll');
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    return await _methods
            .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        true;
  }

  static Future<void> requestIgnoreBatteryOptimizations() {
    return _methods.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  static Future<void> requestPostNotifications() {
    return _methods.invokeMethod('requestPostNotifications');
  }

  static Future<bool> postNotification({
    required String title,
    required String text,
    String? bigText,
  }) async {
    return await _methods.invokeMethod<bool>(
          'postNotification',
          <String, dynamic>{
            'title': title,
            'text': text,
            'bigText': bigText,
          },
        ) ??
        false;
  }
}
