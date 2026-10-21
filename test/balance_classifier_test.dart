import 'package:flutter_test/flutter_test.dart';
import 'package:log_noti/notifications/balance_classifier.dart';
import 'package:log_noti/notifications/notification_payload.dart';

void main() {
  const credit =
      'TK 123456 +500,000 VND. So du: 1,000,000 VND. ND: Thanh toan don hang';
  test('recognizes balance changes in Vietnamese and English', () {
    for (final text in [
      credit,
      'Tài khoản 123 ghi nợ 200.000 VND; số dư 800.000 VND',
      'Account 123 credited USD 50.00'
    ]) {
      expect(BalanceClassifier.matches({'text': text}), isTrue, reason: text);
    }
    expect(BalanceClassifier.matches({'bigText': credit}), isTrue);
    expect(
        BalanceClassifier.matches({'text': credit},
            includes: 'KHÔNG KHỚP\nTHANH TOÁN'),
        isTrue);
    expect(BalanceClassifier.matches({'text': credit}, includes: 'lương'),
        isFalse);
    expect(
        BalanceClassifier.matches({'text': credit},
            includes: 'thanh toán', excludes: 'ĐƠN HÀNG'),
        isFalse);
  });
  test(
      'rejects summaries, OTP, advertising, failed transactions and balance-only notices',
      () {
    expect(BalanceClassifier.matches({'text': credit, 'isGroupSummary': true}),
        isFalse);
    for (final text in [
      'OTP 123456 xác nhận chuyển tiền TK 123 số tiền 500.000 VND',
      'Ưu đãi nhận tiền 500.000 VND vào tài khoản',
      'Tài khoản chuyển tiền 500.000 VND không thành công',
      'Số dư tài khoản 500.000 VND',
      'Đơn hàng đã giao thành công',
      ''
    ]) {
      expect(BalanceClassifier.matches({'text': text}), isFalse, reason: text);
    }
  });
  test('normalizes precomposed and decomposed Vietnamese', () {
    expect(BalanceClassifier.normalize('ĐẶNG  THỊ\nHỒNG'), 'dang thi hong');
    expect(BalanceClassifier.normalize('Ta\u0300i khoa\u0309n'), 'tai khoan');
  });
  test('message sender and fallback content are composed in Dart', () {
    final row = normalizeNotificationPayload({
      'title': '',
      'titleBig': 'Chat',
      'text': 'fallback',
      'messageItems': [
        {'sender': 'An', 'text': 'Xin chào'}
      ]
    });
    expect(row['title'], 'Chat');
    expect(row['text'], 'An: Xin chào');
    expect(
        normalizeNotificationPayload({
          'textLines': [' one ', '', 'two'],
          'tickerText': 'ticker'
        })['text'],
        'one\ntwo');
    expect(normalizeNotificationPayload({})['text'], '');
  });
}
