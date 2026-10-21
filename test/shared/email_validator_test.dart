import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/shared/validators/email_validator.dart';

void main() {
  group('isValidEmail', () {
    test('accepts ordinary addresses and trims whitespace', () {
      expect(isValidEmail('user@example.com'), isTrue);
      expect(isValidEmail('  user.name+tag@mail.example.org '), isTrue);
    });

    test('rejects malformed addresses', () {
      expect(isValidEmail(null), isFalse);
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('user'), isFalse);
      expect(isValidEmail('user@'), isFalse);
      expect(isValidEmail('@example.com'), isFalse);
      expect(isValidEmail('user@example'), isFalse);
      expect(isValidEmail('us er@example.com'), isFalse);
      expect(isValidEmail('user@@example.com'), isFalse);
    });
  });
}
