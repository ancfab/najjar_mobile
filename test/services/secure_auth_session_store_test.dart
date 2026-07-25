// Unit tests for SecureAuthSessionStore against a fake in-memory
// SecureKeyValueStore (no real Keychain/Keystore platform channel) and the
// real shared_preferences plugin mocked at the platform-channel level (as
// SharedPreferences.setMockInitialValues does), matching the convention in
// session_service_test.dart. Covers save/read round trip, every
// missing/malformed-data path treated as "no session", the legacy Boolean
// never counting as a valid secure session, clear's secure-key + legacy-key
// deletion without touching unrelated preferences, and the distinction
// between "no session" and a genuine typed storage failure.
//
// All identifiers below (username, phone, token, bc_customer_no) are
// synthetic fixtures, not real or supplied backend test-account values.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/secure_auth_session_store.dart';
import 'package:anc_fabrics/services/session_storage_exception.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';

import '../helpers/fake_secure_key_value_store.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret-value';
const _sessionKey = 'anc_auth_session_v1';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureKeyValueStore fakeSecureStore;
  late SecureAuthSessionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeSecureStore = FakeSecureKeyValueStore();
    store = SecureAuthSessionStore(secureStore: fakeSecureStore);
  });

  group('save then read', () {
    test('read returns the exact session that was saved', () async {
      final session = _validSession();

      await store.save(session);
      final restored = await store.read();

      expect(restored, session);
    });

    test('save preserves a token containing | byte-for-byte', () async {
      const rawToken = '1|abcDEF1234567890ExampleOpaqueValue';
      await store.save(_validSession(token: rawToken));

      final restored = await store.read();

      expect(restored!.token, rawToken);
    });

    test('save overwrites a prior session', () async {
      await store.save(_validSession());
      final second = _validSession(token: 'synthetic-id|second-token-value');

      await store.save(second);
      final restored = await store.read();

      expect(restored, second);
      expect(fakeSecureStore.deleteCallCount, 0);
    });
  });

  group('read: missing or malformed data returns null', () {
    test('missing secure key returns null', () async {
      expect(await store.read(), isNull);
    });

    test('empty stored value returns null and deletes the key', () async {
      fakeSecureStore.seed(_sessionKey, '');

      final result = await store.read();

      expect(result, isNull);
      expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
    });

    test('malformed JSON returns null and deletes the key', () async {
      fakeSecureStore.seed(_sessionKey, 'not json at all');

      final result = await store.read();

      expect(result, isNull);
      expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
    });

    test('non-object JSON returns null and deletes the key', () async {
      fakeSecureStore.seed(_sessionKey, '[1, 2, 3]');

      final result = await store.read();

      expect(result, isNull);
      expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
    });

    test('incomplete session returns null and deletes the key', () async {
      fakeSecureStore.seed(_sessionKey, '{"schema_version": 1, "token": "x"}');

      final result = await store.read();

      expect(result, isNull);
      expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
    });

    test('empty-token session returns null and deletes the key', () async {
      final json = _validSession().toJson()..['token'] = '';
      fakeSecureStore.seed(_sessionKey, jsonEncode(json));

      final result = await store.read();

      expect(result, isNull);
      expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
    });

    test(
      'unsupported schema version returns null and deletes the key',
      () async {
        final json = _validSession().toJson()..['schema_version'] = 2;
        fakeSecureStore.seed(_sessionKey, jsonEncode(json));

        final result = await store.read();

        expect(result, isNull);
        expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
      },
    );
  });

  group('hasValidSession', () {
    test('is true only when a valid secure session exists', () async {
      await store.save(_validSession());

      expect(await store.hasValidSession(), isTrue);
    });

    test('is false when no secure session exists', () async {
      expect(await store.hasValidSession(), isFalse);
    });

    test(
      'is false when only the legacy SharedPreferences Boolean is true',
      () async {
        SharedPreferences.setMockInitialValues({
          SessionStorageKeys.isLoggedIn: true,
        });

        expect(await store.hasValidSession(), isFalse);
      },
    );
  });

  group('clear', () {
    test('removes the secure session key', () async {
      await store.save(_validSession());

      await store.clear();

      expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
    });

    test('removes the legacy authentication Boolean', () async {
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
      });

      await store.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SessionStorageKeys.isLoggedIn), isFalse);
    });

    test('leaves unrelated SharedPreferences keys untouched', () async {
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
        'theme_mode': 'dark',
        'language': 'en',
      });

      await store.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getString('language'), 'en');
    });

    test('is safe to call when no session exists', () async {
      await store.clear();

      expect(await store.read(), isNull);
    });
  });

  group('clear ordering and failure guarantees', () {
    test('the legacy Boolean is removed even though the secure deletion that '
        'follows it fails, and clear() throws', () async {
      await store.save(_validSession());
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
      });
      fakeSecureStore.deleteError = Exception(
        'simulated Keystore delete failure',
      );

      await expectLater(store.clear(), throwsA(isA<SessionStorageException>()));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SessionStorageKeys.isLoggedIn), isFalse);
    });

    test('when the secure deletion fails, the authoritative token remains '
        'in place', () async {
      await store.save(_validSession());
      fakeSecureStore.deleteError = Exception(
        'simulated Keystore delete failure',
      );

      await expectLater(store.clear(), throwsA(isA<SessionStorageException>()));

      fakeSecureStore.deleteError = null;
      expect(await store.hasValidSession(), isTrue);
    });

    test('a successful clear() removes the secure key only after the legacy '
        'Boolean, leaving neither behind', () async {
      await store.save(_validSession());
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
      });

      await store.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SessionStorageKeys.isLoggedIn), isFalse);
      expect(fakeSecureStore.containsKey(_sessionKey), isFalse);
    });
  });

  group('typed storage failures', () {
    test('read failure maps to SessionStorageException', () async {
      fakeSecureStore.readError = Exception('simulated Keystore read failure');

      await expectLater(store.read(), throwsA(isA<SessionStorageException>()));
    });

    test('write failure maps to SessionStorageException', () async {
      fakeSecureStore.writeError = Exception(
        'simulated Keystore write failure',
      );

      await expectLater(
        store.save(_validSession()),
        throwsA(isA<SessionStorageException>()),
      );
    });

    test('clear delete failure maps to SessionStorageException', () async {
      fakeSecureStore.deleteError = Exception(
        'simulated Keystore delete failure',
      );

      await expectLater(store.clear(), throwsA(isA<SessionStorageException>()));
    });

    test(
      'a read ArgumentError is not mislabeled as a storage failure',
      () async {
        fakeSecureStore.readError = ArgumentError('simulated programmer error');

        await expectLater(store.read(), throwsArgumentError);
      },
    );

    test('a write StateError is not mislabeled as a storage failure', () async {
      fakeSecureStore.writeError = StateError('simulated programmer error');

      try {
        await store.save(_validSession());
        fail('Expected a StateError to propagate unchanged');
      } catch (error) {
        expect(error, isA<StateError>());
        expect(error, isNot(isA<SessionStorageException>()));
      }
    });

    test(
      'SessionStorageException never contains the token or session JSON',
      () async {
        fakeSecureStore.writeError = Exception('simulated failure');
        const secretLookingToken = '1|placeholder-value-should-not-leak';

        try {
          await store.save(_validSession(token: secretLookingToken));
          fail('Expected a SessionStorageException');
        } on SessionStorageException catch (error) {
          expect(error.toString(), isNot(contains(secretLookingToken)));
          expect(error.message, isNot(contains(secretLookingToken)));
        }
      },
    );
  });
}
