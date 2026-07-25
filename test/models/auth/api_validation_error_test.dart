// Unit tests for ApiValidationError.fromJson: the standard credential-error
// and phone-error shapes from the ANC API's 422 contract, plus defensive
// handling of missing/unknown/malformed/non-JSON-object bodies.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/auth/api_validation_error.dart';

void main() {
  group('ApiValidationError.fromJson', () {
    test('parses the standard credential-error shape', () {
      final error = ApiValidationError.fromJson({
        'message': 'The given data was invalid.',
        'errors': {
          'username': ['These credentials do not match our records.'],
        },
      });

      expect(error.message, 'The given data was invalid.');
      expect(
        error.firstErrorFor('username'),
        'These credentials do not match our records.',
      );
      expect(error.phoneError, isNull);
    });

    test('parses a phone-error shape', () {
      final error = ApiValidationError.fromJson({
        'message': 'The given data was invalid.',
        'errors': {
          'phone': ['The phone field format is invalid.'],
        },
      });

      expect(error.phoneError, 'The phone field format is invalid.');
      expect(error.firstErrorFor('username'), isNull);
    });

    test('handles a missing message', () {
      final error = ApiValidationError.fromJson({
        'errors': {
          'phone': ['Invalid.'],
        },
      });

      expect(error.message, isNull);
      expect(error.phoneError, 'Invalid.');
    });

    test('handles missing errors entirely', () {
      final error = ApiValidationError.fromJson({'message': 'Invalid.'});

      expect(error.message, 'Invalid.');
      expect(error.errors, isEmpty);
    });

    test('tolerates unknown error keys', () {
      final error = ApiValidationError.fromJson({
        'errors': {
          'some_unexpected_field': ['Unexpected.'],
        },
      });

      expect(error.firstErrorFor('some_unexpected_field'), 'Unexpected.');
    });

    test('collects multiple messages for one field', () {
      final error = ApiValidationError.fromJson({
        'errors': {
          'phone': ['Too short.', 'Must include a country code.'],
        },
      });

      expect(error.messagesFor('phone'), [
        'Too short.',
        'Must include a country code.',
      ]);
      expect(error.phoneError, 'Too short.');
    });

    test('ignores malformed entries rather than throwing', () {
      final error = ApiValidationError.fromJson({
        'errors': {
          'phone': ['Valid message.', 42, null],
          'username': 'not-a-list-but-a-string',
          'bad_field': 123,
          'empty_field': <String>[],
        },
      });

      expect(error.messagesFor('phone'), ['Valid message.']);
      expect(error.firstErrorFor('username'), 'not-a-list-but-a-string');
      expect(error.errors.containsKey('bad_field'), isFalse);
      expect(error.errors.containsKey('empty_field'), isFalse);
    });

    test('handles a non-map input predictably', () {
      final error = ApiValidationError.fromJson('not a map');

      expect(error.message, isNull);
      expect(error.errors, isEmpty);
    });

    test('handles null input predictably', () {
      final error = ApiValidationError.fromJson(null);

      expect(error.message, isNull);
      expect(error.errors, isEmpty);
    });

    test('firstErrorFor returns null for an absent field', () {
      final error = ApiValidationError.fromJson({
        'errors': <String, dynamic>{},
      });

      expect(error.firstErrorFor('phone'), isNull);
    });
  });
}
