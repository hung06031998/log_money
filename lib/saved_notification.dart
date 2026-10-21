import 'dart:convert';

class SavedNotification {
  const SavedNotification({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.postTime,
    required this.receivedAt,
    required this.isOngoing,
    required this.isGroupSummary,
    this.analysisAttempted = false,
    this.analysisStatus = 'idle',
    this.analysis,
    this.analysisError,
    this.filterMatch,
    this.filterError,
    this.opPackage,
    this.bigText,
    this.subText,
    this.infoText,
    this.summaryText,
    this.conversationTitle,
    this.messages,
    this.channelId,
    this.category,
    this.notificationKey,
    this.tag,
    this.notificationId,
    this.extrasJson,
  });

  final String analysisStatus;
  final bool analysisAttempted;
  final Map<String, dynamic>? analysis;
  final String? analysisError;

  final bool? filterMatch;
  final String? filterError;

  String get filterLabel => filterError != null
      ? 'Lỗi đánh giá: $filterError'
      : filterMatch == null
          ? 'Đang phân loại'
          : filterMatch!
              ? 'Biến động số dư'
              : 'Khác';

  final int id;
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final int postTime;
  final int receivedAt;
  final bool isOngoing;
  final bool isGroupSummary;
  final String? opPackage;
  final String? bigText;
  final String? subText;
  final String? infoText;
  final String? summaryText;
  final String? conversationTitle;
  final String? messages;
  final String? channelId;
  final String? category;
  final String? notificationKey;
  final String? tag;
  final int? notificationId;
  final String? extrasJson;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    if (conversationTitle != null && conversationTitle!.trim().isNotEmpty) {
      return conversationTitle!.trim();
    }
    return appName;
  }

  String get displayBody {
    final candidates = [
      messages,
      text,
      bigText,
      summaryText,
      subText,
      infoText,
    ];
    for (final value in candidates) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '(Không có nội dung)';
  }

  factory SavedNotification.fromMap(Map<dynamic, dynamic> map) {
    return SavedNotification(
      id: (map['id'] as num).toInt(),
      analysisAttempted: map['analysisAttempted'] == true,
      analysisStatus: map['analysisStatus'] as String? ?? 'idle',
      analysis: map['analysisJson'] == null
          ? null
          : Map<String, dynamic>.from(
              jsonDecode(map['analysisJson'] as String) as Map),
      analysisError: map['analysisError'] as String?,
      filterMatch: map['filterMatch'] as bool?,
      filterError: map['filterError'] as String?,
      packageName: (map['packageName'] as String?) ?? '',
      appName: (map['appName'] as String?)?.trim().isNotEmpty == true
          ? map['appName'] as String
          : ((map['packageName'] as String?) ?? 'Ứng dụng'),
      title: (map['title'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      postTime: (map['postTime'] as num?)?.toInt() ?? 0,
      receivedAt: (map['receivedAt'] as num?)?.toInt() ?? 0,
      isOngoing: map['isOngoing'] == true,
      isGroupSummary: map['isGroupSummary'] == true,
      opPackage: map['opPackage'] as String?,
      bigText: map['bigText'] as String?,
      subText: map['subText'] as String?,
      infoText: map['infoText'] as String?,
      summaryText: map['summaryText'] as String?,
      conversationTitle: map['conversationTitle'] as String?,
      messages: map['messages'] as String?,
      channelId: map['channelId'] as String?,
      category: map['category'] as String?,
      notificationKey: map['notificationKey'] as String?,
      tag: map['tag'] as String?,
      notificationId: (map['notificationId'] as num?)?.toInt(),
      extrasJson: map['extrasJson'] as String?,
    );
  }
}
