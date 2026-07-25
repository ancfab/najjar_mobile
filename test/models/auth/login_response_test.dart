// Unit tests for AuthenticatedUser.fromJson and LoginResponse.fromJson
// (combined here since the response always nests the user). Covers
// successful parsing, the nullable bc_customer_no, the top-level-preferred
// must_change_password normalization, and controlled FormatException
// failures for malformed/missing required data.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/auth/authenticated_user.dart';
import 'package:anc_fabrics/models/auth/login_response.dart';

Map<String, dynamic> _validUserJson() => {
  'id': 1,
  'username': 'sample.user',
  'phone': '+96890000000',
  'country': 'OM',
  'client_id': 'ANCNAJJAR',
  'bc_customer_no': 'SAMPLE-0001',
  'must_change_password': false,
};

Map<String, dynamic> _validLoginJson() => {
  'token': 'synthetic-id|synthetic-secret',
  'must_change_password': false,
  'user': _validUserJson(),
};

void main() {
  group('AuthenticatedUser.fromJson', () {
    test('parses a well-formed user', () {
      final user = AuthenticatedUser.fromJson(_validUserJson());

      expect(user.id, 1);
      expect(user.username, 'sample.user');
      expect(user.phone, '+96890000000');
      expect(user.country, 'OM');
      expect(user.clientId, 'ANCNAJJAR');
      expect(user.bcCustomerNo, 'SAMPLE-0001');
      expect(user.mustChangePassword, isFalse);
    });

    test('accepts a null bc_customer_no', () {
      final json = _validUserJson()..['bc_customer_no'] = null;

      expect(AuthenticatedUser.fromJson(json).bcCustomerNo, isNull);
    });

    test('accepts a missing bc_customer_no key entirely', () {
      final json = _validUserJson()..remove('bc_customer_no');

      expect(AuthenticatedUser.fromJson(json).bcCustomerNo, isNull);
    });

    test('maps client_id to clientId', () {
      expect(
        AuthenticatedUser.fromJson(_validUserJson()).clientId,
        'ANCNAJJAR',
      );
    });

    test('maps must_change_password to mustChangePassword', () {
      final json = _validUserJson()..['must_change_password'] = true;

      expect(AuthenticatedUser.fromJson(json).mustChangePassword, isTrue);
    });

    test('throws FormatException when id is missing', () {
      final json = _validUserJson()..remove('id');

      expect(() => AuthenticatedUser.fromJson(json), throwsFormatException);
    });

    test('throws FormatException when id is not an int', () {
      final json = _validUserJson()..['id'] = 'not-an-int';

      expect(() => AuthenticatedUser.fromJson(json), throwsFormatException);
    });

    test('throws FormatException when username is empty', () {
      final json = _validUserJson()..['username'] = '';

      expect(() => AuthenticatedUser.fromJson(json), throwsFormatException);
    });

    test('throws FormatException when bc_customer_no is not a string', () {
      final json = _validUserJson()..['bc_customer_no'] = 42;

      expect(() => AuthenticatedUser.fromJson(json), throwsFormatException);
    });

    test('throws FormatException when must_change_password is not a bool', () {
      final json = _validUserJson()..['must_change_password'] = 'false';

      expect(() => AuthenticatedUser.fromJson(json), throwsFormatException);
    });
  });

  group('LoginResponse.fromJson', () {
    test('parses a well-formed success response', () {
      final response = LoginResponse.fromJson(_validLoginJson());

      expect(response.token, 'synthetic-id|synthetic-secret');
      expect(response.mustChangePassword, isFalse);
      expect(response.user.username, 'sample.user');
    });

    test('preserves a Sanctum-style token containing | byte-for-byte', () {
      const rawToken = '1|abcDEF1234567890ExampleOpaqueValue';
      final json = _validLoginJson()..['token'] = rawToken;

      expect(LoginResponse.fromJson(json).token, rawToken);
    });

    test(
      'prefers the top-level must_change_password over the nested value',
      () {
        final json = _validLoginJson();
        json['must_change_password'] = true;
        (json['user'] as Map<String, dynamic>)['must_change_password'] = false;

        expect(LoginResponse.fromJson(json).mustChangePassword, isTrue);
      },
    );

    test(
      'falls back to the nested value only when the top-level field is absent',
      () {
        final json = _validLoginJson()..remove('must_change_password');
        (json['user'] as Map<String, dynamic>)['must_change_password'] = true;

        expect(LoginResponse.fromJson(json).mustChangePassword, isTrue);
      },
    );

    test(
      'deterministically resolves disagreement in favor of the top-level value',
      () {
        Map<String, dynamic> conflicting() {
          final json = _validLoginJson();
          json['must_change_password'] = false;
          (json['user'] as Map<String, dynamic>)['must_change_password'] = true;
          return json;
        }

        expect(
          LoginResponse.fromJson(conflicting()).mustChangePassword,
          isFalse,
        );
        expect(
          LoginResponse.fromJson(conflicting()).mustChangePassword,
          isFalse,
        );
      },
    );

    test('rejects an empty token', () {
      final json = _validLoginJson()..['token'] = '';

      expect(() => LoginResponse.fromJson(json), throwsFormatException);
    });

    test('rejects a missing token', () {
      final json = _validLoginJson()..remove('token');

      expect(() => LoginResponse.fromJson(json), throwsFormatException);
    });

    test('rejects a missing user object', () {
      final json = _validLoginJson()..remove('user');

      expect(() => LoginResponse.fromJson(json), throwsFormatException);
    });

    test('rejects a malformed nested user', () {
      final json = _validLoginJson()..['user'] = {'id': 1};

      expect(() => LoginResponse.fromJson(json), throwsFormatException);
    });

    test('parsing-failure messages never include the token value', () {
      const secretLookingToken = '1|placeholder-value-should-not-leak';
      final json = _validLoginJson()
        ..['token'] = secretLookingToken
        ..['user'] = {'id': 1};

      try {
        LoginResponse.fromJson(json);
        fail('Expected a FormatException');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains(secretLookingToken)));
      }
    });
  });
}
