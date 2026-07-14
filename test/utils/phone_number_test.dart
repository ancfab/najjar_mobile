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
}
