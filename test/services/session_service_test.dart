// Unit tests for SecureSessionService, the production SessionService — a
// thin façade over SecureAuthSessionStore. Verifies isLoggedIn/endSession
// delegate correctly, that the legacy SharedPreferences Boolean never
// authenticates the user, and that a genuine secure-storage failure on
// endSession is a typed throw rather than a silent success. Uses a fake
// in-memory SecureKeyValueStore — no real Keychain/Keystore platform
// channel — and the real shared_preferences plugin mocked at the
// platform-channel level.
//
// All identifiers below (username, phone, token, bc_customer_no) are
// synthetic fixtures, not real or supplied backend test-account values.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/secure_auth_session_store.dart';
import 'package:anc_fabrics/services/session_service.dart';
import 'package:anc_fabrics/services/session_storage_exception.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';

import '../helpers/fake_secure_key_value_store.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

AuthSession _validSession() => const AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: 'sample.user',
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureKeyValueStore fakeSecureStore;
  late SecureAuthSessionStore authSessionStore;
  late SecureSessionService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeSecureStore = FakeSecureKeyValueStore();
    authSessionStore = SecureAuthSessionStore(secureStore: fakeSecureStore);
    service = SecureSessionService(sessionStore: authSessionStore);
  });

  group('isLoggedIn', () {
    test('is false when no secure session exists', () async {
      expect(await service.isLoggedIn(), isFalse);
    });

    test('is true once a secure session has been saved', () async {
      await authSessionStore.save(_validSession());

      expect(await service.isLoggedIn(), isTrue);
    });

    test(
      'a legacy Boolean set to true does not authenticate the user',
      () async {
        SharedPreferences.setMockInitialValues({
          SessionStorageKeys.isLoggedIn: true,
        });

        expect(await service.isLoggedIn(), isFalse);
      },
    );
  });

  group('endSession', () {
    test('clears the secure session', () async {
      await authSessionStore.save(_validSession());

      await service.endSession();

      expect(await service.isLoggedIn(), isFalse);
    });

    test('clears the legacy Boolean', () async {
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
      });

      await service.endSession();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SessionStorageKeys.isLoggedIn), isFalse);
    });

    test('leaves unrelated SharedPreferences keys untouched', () async {
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
        'theme_mode': 'dark',
        'language': 'en',
      });

      await service.endSession();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getString('language'), 'en');
    });

    test('is safe to call when no session was ever started', () async {
      await service.endSession();

      expect(await service.isLoggedIn(), isFalse);
    });

    test('a secure-storage failure throws SessionStorageException and leaves '
        'the token intact', () async {
      await authSessionStore.save(_validSession());
      fakeSecureStore.deleteError = Exception(
        'simulated Keystore delete failure',
      );

      await expectLater(
        service.endSession(),
        throwsA(isA<SessionStorageException>()),
      );

      // The authoritative secure session is still present — a failed
      // endSession() must never look like a successful sign-out.
      fakeSecureStore.deleteError = null;
      expect(await service.isLoggedIn(), isTrue);
    });
  });

  group('production default', () {
    test('constructing without an injected store does not throw', () {
      // FlutterSecureStorage's constructor is a plain Dart object — no
      // platform channel call happens until read/write/delete is actually
      // invoked, so this must be safe in any test environment.
      expect(SecureSessionService.new, returnsNormally);
    });
  });
}
