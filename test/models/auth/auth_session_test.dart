// Unit tests for AuthSession: construction, mapping from LoginResponse,
// exact token preservation, JSON round trip, and controlled FormatException
// failures for malformed persisted data.
//
// All identifiers below (username, phone, token, bc_customer_no) are
// synthetic fixtures, not real or supplied backend test-account values.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/auth/authenticated_user.dart';
import 'package:anc_fabrics/models/auth/login_response.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret-value';

AuthSession _validSession({String token = _syntheticToken}) => AuthSession(
  token: token,
  userId: 7,
  username: 'sample.user',
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

Map<String, dynamic> _validEnvelope() => {
  'schema_version': 1,
  'token': _syntheticToken,
  'user_id': 7,
  'username': 'sample.user',
  'phone': '+96890000000',
  'country': 'OM',
  'client_id': 'ANCNAJJAR',
  'bc_customer_no': 'SAMPLE-0001',
  'must_change_password': false,
};

LoginResponse _validLoginResponse({bool mustChangePassword = false}) =>
    LoginResponse(
      token: _syntheticToken,
      mustChangePassword: mustChangePassword,
      user: const AuthenticatedUser(
        id: 7,
        username: 'sample.user',
        phone: '+96890000000',
        country: 'OM',
        clientId: 'ANCNAJJAR',
        bcCustomerNo: 'SAMPLE-0001',
        mustChangePassword: false,
      ),
    );

void main() {
  group('AuthSession construction', () {
    test('constructs successfully with all fields', () {
      final session = _validSession();

      expect(session.token, _syntheticToken);
      expect(session.userId, 7);
      expect(session.username, 'sample.user');
      expect(session.phone, '+96890000000');
      expect(session.country, 'OM');
      expect(session.clientId, 'ANCNAJJAR');
      expect(session.bcCustomerNo, 'SAMPLE-0001');
      expect(session.mustChangePassword, isFalse);
    });

    test('accepts a null bcCustomerNo', () {
      final session = AuthSession(
        token: _syntheticToken,
        userId: 7,
        username: 'sample.user',
        phone: '+96890000000',
        country: 'OM',
        clientId: 'ANCNAJJAR',
        mustChangePassword: false,
      );

      expect(session.bcCustomerNo, isNull);
    });

    test('does not reveal the token in toString', () {
      final session = _validSession();

      expect(session.toString(), isNot(contains(_syntheticToken)));
    });

    test('equality holds for sessions with identical fields', () {
      expect(_validSession(), _validSession());
    });
  });

  group('AuthSession.fromLoginResponse', () {
    test('maps every field from the login response', () {
      final session = AuthSession.fromLoginResponse(_validLoginResponse());

      expect(session.token, _syntheticToken);
      expect(session.userId, 7);
      expect(session.username, 'sample.user');
      expect(session.phone, '+96890000000');
      expect(session.country, 'OM');
      expect(session.clientId, 'ANCNAJJAR');
      expect(session.bcCustomerNo, 'SAMPLE-0001');
    });

    test('preserves a token containing | byte-for-byte', () {
      const rawToken = '1|abcDEF1234567890ExampleOpaqueValue';
      final response = LoginResponse(
        token: rawToken,
        mustChangePassword: false,
        user: const AuthenticatedUser(
          id: 7,
          username: 'sample.user',
          phone: '+96890000000',
          country: 'OM',
          clientId: 'ANCNAJJAR',
          bcCustomerNo: null,
          mustChangePassword: false,
        ),
      );

      expect(AuthSession.fromLoginResponse(response).token, rawToken);
    });

    test('persists the normalized top-level mustChangePassword value', () {
      final response = _validLoginResponse(mustChangePassword: true);

      expect(
        AuthSession.fromLoginResponse(response).mustChangePassword,
        isTrue,
      );
    });
  });

  group('AuthSession JSON round trip', () {
    test('toJson produces the versioned envelope', () {
      final json = _validSession().toJson();

      expect(json, _validEnvelope());
    });

    test('fromJson parses a well-formed envelope', () {
      final session = AuthSession.fromJson(_validEnvelope());

      expect(session, _validSession());
    });

    test('round trips through toJson/fromJson unchanged', () {
      final original = _validSession();

      final restored = AuthSession.fromJson(original.toJson());

      expect(restored, original);
    });

    test('round trip preserves a token containing | byte-for-byte', () {
      const rawToken = '1|abcDEF1234567890ExampleOpaqueValue';
      final original = _validSession(token: rawToken);

      final restored = AuthSession.fromJson(original.toJson());

      expect(restored.token, rawToken);
    });

    test('round trips a null bcCustomerNo', () {
      final original = AuthSession(
        token: _syntheticToken,
        userId: 7,
        username: 'sample.user',
        phone: '+96890000000',
        country: 'OM',
        clientId: 'ANCNAJJAR',
        mustChangePassword: false,
      );

      final restored = AuthSession.fromJson(original.toJson());

      expect(restored.bcCustomerNo, isNull);
    });

    test('serialized JSON never contains a password key', () {
      final json = _validSession().toJson();

      expect(json.containsKey('password'), isFalse);
    });
  });

  group('AuthSession.fromJson rejects malformed data', () {
    test('rejects an empty token', () {
      final json = _validEnvelope()..['token'] = '';

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a missing token', () {
      final json = _validEnvelope()..remove('token');

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a missing user_id', () {
      final json = _validEnvelope()..remove('user_id');

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a wrong-typed user_id', () {
      final json = _validEnvelope()..['user_id'] = 'not-an-int';

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a wrong-typed username', () {
      final json = _validEnvelope()..['username'] = 42;

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a wrong-typed must_change_password', () {
      final json = _validEnvelope()..['must_change_password'] = 'false';

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a non-string bc_customer_no', () {
      final json = _validEnvelope()..['bc_customer_no'] = 42;

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects a missing schema_version', () {
      final json = _validEnvelope()..remove('schema_version');

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('rejects an unsupported schema_version', () {
      final json = _validEnvelope()..['schema_version'] = 2;

      expect(() => AuthSession.fromJson(json), throwsFormatException);
    });

    test('parsing-failure messages never include the token value', () {
      const secretLookingToken = '1|placeholder-value-should-not-leak';
      final json = _validEnvelope()
        ..['token'] = secretLookingToken
        ..['user_id'] = 'not-an-int';

      try {
        AuthSession.fromJson(json);
        fail('Expected a FormatException');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains(secretLookingToken)));
      }
    });
  });
}
