import 'dart:convert';
import 'notification_payload.dart';
import 'package:flutter/services.dart';

/// SQL and migrations live in Dart. Android only executes bound statements.
class NotificationStore {
  NotificationStore(this.bridge);
  final MethodChannel bridge;

  Future<List<Map<String, dynamic>>> query(String sql,
      [List<Object?> args = const []]) async {
    final rows = await bridge
        .invokeListMethod<dynamic>('query', {'sql': sql, 'args': args});
    return (rows ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> execute(String sql, [List<Object?> args = const []]) =>
      transaction([
        {'sql': sql, 'args': args}
      ]);

  Future<void> transaction(List<Map<String, dynamic>> statements) =>
      bridge.invokeMethod('execute', {'statements': statements});

  static const columns = {
    'packageName': 'package_name',
    'opPackage': 'op_package',
    'appName': 'app_name',
    'title': 'title',
    'text': 'text',
    'bigText': 'big_text',
    'subText': 'sub_text',
    'infoText': 'info_text',
    'summaryText': 'summary_text',
    'conversationTitle': 'conversation_title',
    'messages': 'messages',
    'channelId': 'channel_id',
    'category': 'category',
    'notificationKey': 'notification_key',
    'tag': 'tag',
    'notificationId': 'notification_id',
    'postTime': 'post_time',
    'receivedAt': 'received_at',
    'isOngoing': 'is_ongoing',
    'isGroupSummary': 'is_group_summary',
    'extrasJson': 'extras_json',
    'filterMatch': 'filter_match',
    'filterError': 'filter_error',
    'analysisAttempted': 'analysis_attempted',
    'analysisJson': 'analysis_json',
    'analysisError': 'analysis_error',
  };
  static const booleans = {
    'isOngoing',
    'isGroupSummary',
    'filterMatch',
    'analysisAttempted'
  };

  static Map<String, dynamic> decodeRow(Map<String, dynamic> row) => {
        'id': row['id'],
        for (final entry in columns.entries)
          entry.key: booleans.contains(entry.key) && row[entry.value] != null
              ? row[entry.value] == 1
              : row[entry.value],
      };

  Future<void> initialize() async {
    final version =
        (await query('PRAGMA user_version')).single['user_version'] as int;
    if (version > 3) throw StateError('Phiên bản dữ liệu mới hơn ứng dụng.');
    final statements = <String>[];
    if (version == 0) {
      statements.addAll(schema);
    } else {
      if (version < 2) {
        statements.addAll([
          'ALTER TABLE notifications ADD COLUMN filter_match INTEGER',
          'ALTER TABLE notifications ADD COLUMN filter_error TEXT',
        ]);
      }
      if (version < 3) {
        statements.addAll([
          'ALTER TABLE notifications ADD COLUMN analysis_attempted INTEGER NOT NULL DEFAULT 0',
          'ALTER TABLE notifications ADD COLUMN analysis_json TEXT',
          'ALTER TABLE notifications ADD COLUMN analysis_error TEXT',
          'UPDATE notifications SET filter_match = NULL, filter_error = NULL',
        ]);
      }
    }
    if (version < 3) {
      await transaction([...statements, 'PRAGMA user_version = 3']
          .map((sql) => <String, dynamic>{'sql': sql})
          .toList());
    }
  }

  /// Insert + acknowledge in one transaction. A process restart can replay safely.
  Future<Map<String, dynamic>?> importInbox(Map<String, dynamic> inbox) async {
    final payload = normalizeNotificationPayload(Map<String, dynamic>.from(
        jsonDecode(inbox['payload'] as String) as Map));
    final existing = await query(
        'SELECT id FROM notifications WHERE notification_key = ? AND post_time = ? AND title = ? AND text = ?',
        [
          payload['notificationKey'],
          payload['postTime'],
          payload['title'],
          payload['text']
        ]);
    final fields = columns.entries
        .takeWhile((entry) => entry.key != 'filterMatch')
        .toList();
    await transaction([
      {
        'sql':
            'INSERT OR IGNORE INTO notifications (${fields.map((e) => e.value).join(',')}) VALUES (${List.filled(fields.length, '?').join(',')})',
        'args': fields
            .map((e) => booleans.contains(e.key)
                ? (payload[e.key] == true ? 1 : 0)
                : payload[e.key])
            .toList()
      },
      {
        'sql': 'DELETE FROM native_inbox WHERE id = ?',
        'args': [inbox['id']]
      },
    ]);
    if (existing.isNotEmpty) return null;
    final rows = await query(
        'SELECT * FROM notifications WHERE notification_key = ? AND post_time = ? AND title = ? AND text = ?',
        [
          payload['notificationKey'],
          payload['postTime'],
          payload['title'],
          payload['text']
        ]);
    return rows.isEmpty ? null : decodeRow(rows.single);
  }

  Future<Map<String, dynamic>> getById(int id) async {
    final rows = await query('SELECT * FROM notifications WHERE id = ?', [id]);
    if (rows.isEmpty) {
      throw PlatformException(
          code: 'analysis', message: 'Thông báo không còn tồn tại.');
    }
    return decodeRow(rows.single);
  }

  static ({String where, List<Object?> args}) selection(
      String? query, String? filter) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      clauses.add(
          '(app_name LIKE ? COLLATE NOCASE OR title LIKE ? COLLATE NOCASE OR text LIKE ? COLLATE NOCASE OR package_name LIKE ? COLLATE NOCASE)');
      args.addAll(List.filled(4, '%$query%'));
    }
    if (filter == 'matched') clauses.add('filter_match = 1');
    if (filter == 'unmatched') clauses.add('filter_match = 0');
    return (
      where: clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}',
      args: args
    );
  }

  Future<List<Map<String, dynamic>>> notifications(Map args) async {
    final selection = NotificationStore.selection(
        args['query'] as String?, args['filter'] as String?);
    return (await query(
            'SELECT * FROM notifications ${selection.where} ORDER BY received_at DESC, id DESC LIMIT ? OFFSET ?',
            [
          ...selection.args,
          ((args['limit'] as int?) ?? 50).clamp(1, 500),
          ((args['offset'] as int?) ?? 0).clamp(0, 1 << 31)
        ]))
        .map(decodeRow)
        .toList();
  }

  Future<int> count(Map args) async {
    final selection = NotificationStore.selection(
        args['query'] as String?, args['filter'] as String?);
    return (await query(
            'SELECT COUNT(*) AS count FROM notifications ${selection.where}',
            selection.args))
        .single['count'] as int;
  }

  Future<void> saveAnalysis(int id, String? json, String? error) => execute(
      'UPDATE notifications SET analysis_attempted = 1, analysis_json = ?, analysis_error = ? WHERE id = ?',
      [json, error, id]);

  static const schema = <String>[
    '''CREATE TABLE notifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                package_name TEXT NOT NULL,
                op_package TEXT,
                app_name TEXT,
                title TEXT NOT NULL DEFAULT '',
                text TEXT NOT NULL DEFAULT '',
                big_text TEXT,
                sub_text TEXT,
                info_text TEXT,
                summary_text TEXT,
                conversation_title TEXT,
                messages TEXT,
                channel_id TEXT,
                category TEXT,
                notification_key TEXT NOT NULL DEFAULT '',
                tag TEXT,
                notification_id INTEGER,
                post_time INTEGER NOT NULL,
                received_at INTEGER NOT NULL,
                is_ongoing INTEGER NOT NULL DEFAULT 0,
                is_group_summary INTEGER NOT NULL DEFAULT 0,
                extras_json TEXT,
                filter_match INTEGER,
                filter_error TEXT,
                analysis_attempted INTEGER NOT NULL DEFAULT 0,
                analysis_json TEXT,
                analysis_error TEXT
            )''',
    'CREATE INDEX idx_notifications_received_at ON notifications(received_at DESC, id DESC)',
    'CREATE INDEX idx_notifications_package ON notifications(package_name)',
    'CREATE UNIQUE INDEX idx_notifications_dedupe ON notifications(notification_key, post_time, title, text)',
  ];
}
