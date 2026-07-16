import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/utils/user_initials.dart';

void main() {
  group('userInitials', () {
    test('derives initials from a first and last name', () {
      expect(userInitials('Alex Sterling'), 'AS');
    });

    test('derives a single initial from a one-word name', () {
      expect(userInitials('Madonna'), 'M');
    });

    test('uses only the first and last word for multi-word names', () {
      expect(userInitials('Mary Jane Watson'), 'MW');
    });

    test('falls back to the default when the name is empty', () {
      expect(userInitials(''), 'JD');
    });

    test('falls back to the default when the name is whitespace-only', () {
      expect(userInitials('   '), 'JD');
    });

    test('supports a custom fallback', () {
      expect(userInitials('', fallback: 'XX'), 'XX');
    });
  });
}
