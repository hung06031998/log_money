/// Choose display content from the raw Android fields in one testable place.
Map<String, dynamic> normalizeNotificationPayload(Map<String, dynamic> raw) {
  String first(Iterable<dynamic> values) => values
      .whereType<String>()
      .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
  final items = raw['messageItems'] as List?;
  final messages = items == null
      ? raw['messages'] as String? ?? ''
      : items
          .where((item) => (item['text'] as String? ?? '').trim().isNotEmpty)
          .map((item) {
          final sender = item['sender'] as String? ?? '';
          final text = item['text'] as String? ?? '';
          return sender.trim().isEmpty ? text : '$sender: $text';
        }).join('\n');
  final lines = (raw['textLines'] as List? ?? [])
      .whereType<String>()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
  return {
    ...raw,
    'title': first([raw['title'], raw['titleBig'], raw['tickerText']]),
    'text': first([
      messages,
      raw['text'],
      lines,
      raw['bigText'],
      raw['infoText'],
      raw['tickerText']
    ]),
    'messages': messages.trim().isEmpty ? null : messages,
  };
}
