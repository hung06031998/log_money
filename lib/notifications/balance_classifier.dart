/// Local balance-change recognition. No Android APIs or network calls.
class BalanceClassifier {
  static String normalize(String value) {
    var result = value.toLowerCase();
    const accents = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    for (final entry in accents.entries) {
      result = result.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return result
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool matches(Map<String, dynamic> row,
      {String includes = '', String excludes = ''}) {
    if (row['isGroupSummary'] == true) return false;
    final content = normalize([
      'title',
      'text',
      'bigText',
      'subText',
      'infoText',
      'summaryText',
      'conversationTitle',
      'messages',
    ].map((key) => row[key]).whereType<String>().join('\n'));
    Iterable<String> terms(String value) =>
        value.split('\n').map(normalize).where((term) => term.isNotEmpty);
    if (terms(excludes).any(content.contains)) return false;
    final required = terms(includes);
    if (required.isNotEmpty && !required.any(content.contains)) return false;
    if (RegExp(
            r'\b(otp|ma xac thuc|ma xac nhan|verification code|khuyen mai|uu dai|vay ngay|giao dich that bai|khong thanh cong|du kien)\b')
        .hasMatch(content)) return false;
    final amount = RegExp(
            r'(?:[+−-]\s*\d[\d.,]*\s*(?:vnd|vnđ|d|dong|usd|eur)\b|\d[\d.,]*\s*(?:vnd|vnđ|dong|usd|eur)\b|(?:vnd|usd|eur)\s*[+−-]?\s*\d|[+−-]\s*\d[\d.,]*)')
        .hasMatch(content);
    final account = RegExp(r'\b(tk|tai khoan|account|so du|sd|balance|the)\b')
        .hasMatch(content);
    final movement = RegExp(
            r'\b(bien dong|ghi co|ghi no|bao co|bao no|nhan tien|nhan duoc|chuyen tien|chuyen khoan|thanh toan|rut tien|phat sinh|credited|debited|received|tang|giam)\b|[+−-]\s*\d')
        .hasMatch(content);
    return amount && account && movement;
  }
}
