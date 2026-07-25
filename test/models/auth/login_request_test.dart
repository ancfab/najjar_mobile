// Unit tests for LoginRequest.toJson: verifies the exact backend field
// names (including the snake_case client_id) and that the password is
// serialized unmodified. Uses only synthetic, non-real test values.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/auth/login_request.dart';

void main() {
  group('LoginRequest.toJson', () {
    const request = LoginRequest(
      country: 'OM',
      phone: '+96890000000',
      username: 'sample.user',
      clientId: 'ANCNAJJAR',
      password: 'placeholder-test-value',
    );

    test('produces exactly the backend field names', () {
      final json = request.toJson();

      expect(json.keys.toSet(), {
        'country',
        'phone',
        'username',
        'client_id',
        'password',
      });
    });

    test('serializes client_id in snake_case, not clientId', () {
      final json = request.toJson();

      expect(json.containsKey('client_id'), isTrue);
      expect(json.containsKey('clientId'), isFalse);
    });

    test('serializes the exact field values', () {
      final json = request.toJson();

      expect(json['country'], 'OM');
      expect(json['phone'], '+96890000000');
      expect(json['username'], 'sample.user');
      expect(json['client_id'], 'ANCNAJJAR');
      expect(json['password'], 'placeholder-test-value');
    });

    test('does not trim or otherwise modify the password', () {
      const padded = LoginRequest(
        country: 'OM',
        phone: '+96890000000',
        username: 'sample.user',
        clientId: 'ANCNAJJAR',
        password: '  spaced-out-placeholder  ',
      );

      expect(padded.toJson()['password'], '  spaced-out-placeholder  ');
    });

    test('contains no Authorization-related key', () {
      final json = request.toJson();

      expect(json.containsKey('Authorization'), isFalse);
      expect(json.containsKey('authorization'), isFalse);
      expect(json.containsKey('token'), isFalse);
    });
  });
}
