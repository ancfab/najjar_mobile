// Unit tests for the WhatsApp phone-number normalization helper: digit
// extraction, formatting-character stripping, and rejection of invalid
// input.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/utils/phone_number.dart';

void main() {
  group('normalizeWhatsAppNumber', () {
    test('strips spaces and the leading + while keeping the country code', () {
      expect(normalizeWhatsAppNumber('+961 3 123 456'), '9613123456');
    });

    test('strips hyphens and the leading + while keeping the country code', () {
      expect(normalizeWhatsAppNumber('+971-50-123-4567'), '971501234567');
    });

    test('strips parentheses and other display formatting', () {
      expect(normalizeWhatsAppNumber('+1 (555) 123-4567'), '15551234567');
    });

    test('returns null for null input', () {
      expect(normalizeWhatsAppNumber(null), isNull);
    });

    test('returns null for an empty string', () {
      expect(normalizeWhatsAppNumber(''), isNull);
    });

    test('returns null for a blank string', () {
      expect(normalizeWhatsAppNumber('   '), isNull);
    });

    test('returns null when there is no leading + (no country-code '
        'guessing)', () {
      expect(normalizeWhatsAppNumber('0501234567'), isNull);
    });

    test('returns null for a too-short number', () {
      expect(normalizeWhatsAppNumber('+123'), isNull);
    });

    test('returns null for a too-long number', () {
      expect(normalizeWhatsAppNumber('+1234567890123456'), isNull);
    });

    test('returns null for a + with no digits', () {
      expect(normalizeWhatsAppNumber('+'), isNull);
    });
  });

  group('normalizePhoneNumberForTel', () {
    test('preserves the leading + and strips spaces', () {
      expect(normalizePhoneNumberForTel('+961 1 275 019'), '+9611275019');
    });

    test('preserves the leading + and strips hyphens', () {
      expect(normalizePhoneNumberForTel('+971-4-123-4567'), '+97141234567');
    });

    test('strips parentheses and other display formatting', () {
      expect(normalizePhoneNumberForTel('+1 (555) 123-4567'), '+15551234567');
    });

    test('normalizes a local number without a leading + and without guessing '
        'a country code', () {
      expect(normalizePhoneNumberForTel('(01) 234 567'), '01234567');
    });

    test('returns null for null input', () {
      expect(normalizePhoneNumberForTel(null), isNull);
    });

    test('returns null for an empty string', () {
      expect(normalizePhoneNumberForTel(''), isNull);
    });

    test('returns null for a blank string', () {
      expect(normalizePhoneNumberForTel('   '), isNull);
    });

    test('returns null for a + with no digits', () {
      expect(normalizePhoneNumberForTel('+'), isNull);
    });

    test('returns null for formatting characters with no digits', () {
      expect(normalizePhoneNumberForTel('(--)'), isNull);
    });
  });
}
