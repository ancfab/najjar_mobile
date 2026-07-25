// Tests for MyApp's startup auth gate: given the persisted-session state
// main() resolves before calling runApp, does the app open on Login or on
// an authenticated screen? This is what stops a relaunch after logout from
// reopening on Home (or any other authenticated screen).
//
// Also covers resolveStartupSession directly — the pure function that
// decides that state from a SessionService — against a real
// SecureSessionService/SecureAuthSessionStore wired to a fake in-memory
// SecureKeyValueStore (never a real Keychain/Keystore platform channel),
// proving the valid/missing/corrupted/legacy-Boolean/storage-failure cases
// all resolve safely and that a storage failure never falls back to the
// legacy Boolean.
//
// All identifiers below (username, phone, token, bc_customer_no) are
// synthetic fixtures, not real or supplied backend test-account values.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/main.dart';
import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/services/secure_auth_session_store.dart';
import 'package:anc_fabrics/services/session_service.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';

import 'helpers/fake_secure_key_value_store.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';
const _sessionKey = 'anc_auth_session_v1';

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

  testWidgets(
    'Defaults to Login when constructed without an explicit session state '
    '(matches a fresh, logged-out install)',
    (tester) async {
      await tester.pumpWidget(const MyApp());

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets(
    'Opens on Login when the startup session check reports logged out '
    '(e.g. after logout cleared the session)',
    (tester) async {
      await tester.pumpWidget(const MyApp(isLoggedIn: false));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets('Opens on Home when the startup session check reports an active '
      'session', (tester) async {
    await tester.pumpWidget(const MyApp(isLoggedIn: true));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('Shows the startup message once on Login after a secure-session '
      'restore failure', (tester) async {
    const message =
        'We could not restore your secure session. Please sign in again.';

    await tester.pumpWidget(
      const MyApp(isLoggedIn: false, startupMessage: message),
    );
    await tester.pump(); // let the post-frame callback fire
    await tester.pump(); // let the SnackBar animate in

    expect(find.text(message), findsOneWidget);
  });

  testWidgets('Shows no startup message when none is supplied', (tester) async {
    await tester.pumpWidget(const MyApp(isLoggedIn: false));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  group('resolveStartupSession', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    SecureSessionService serviceOver(FakeSecureKeyValueStore fakeStore) =>
        SecureSessionService(
          sessionStore: SecureAuthSessionStore(secureStore: fakeStore),
        );

    test('a valid secure session resolves isLoggedIn true', () async {
      final fakeStore = FakeSecureKeyValueStore();
      await SecureAuthSessionStore(
        secureStore: fakeStore,
      ).save(_validSession());

      final result = await resolveStartupSession(serviceOver(fakeStore));

      expect(result.isLoggedIn, isTrue);
      expect(result.startupMessage, isNull);
    });

    test('no secure session resolves isLoggedIn false', () async {
      final result = await resolveStartupSession(
        serviceOver(FakeSecureKeyValueStore()),
      );

      expect(result.isLoggedIn, isFalse);
      expect(result.startupMessage, isNull);
    });

    test('the legacy Boolean alone resolves isLoggedIn false', () async {
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
      });

      final result = await resolveStartupSession(
        serviceOver(FakeSecureKeyValueStore()),
      );

      expect(result.isLoggedIn, isFalse);
    });

    test('a corrupted secure session resolves isLoggedIn false', () async {
      final fakeStore = FakeSecureKeyValueStore()
        ..seed(_sessionKey, 'not json at all');

      final result = await resolveStartupSession(serviceOver(fakeStore));

      expect(result.isLoggedIn, isFalse);
    });

    test(
      'an unsupported secure-session schema resolves isLoggedIn false',
      () async {
        final json = _validSession().toJson()..['schema_version'] = 2;
        final fakeStore = FakeSecureKeyValueStore()
          ..seed(_sessionKey, jsonEncode(json));

        final result = await resolveStartupSession(serviceOver(fakeStore));

        expect(result.isLoggedIn, isFalse);
      },
    );

    test('a secure-storage read failure does not crash startup and returns a '
        'safe message', () async {
      final fakeStore = FakeSecureKeyValueStore()
        ..readError = Exception('simulated Keystore read failure');

      final result = await resolveStartupSession(serviceOver(fakeStore));

      expect(result.isLoggedIn, isFalse);
      expect(result.startupMessage, isNotNull);
      expect(result.startupMessage, isNot(contains('Keystore')));
    });

    test(
      'a secure-storage failure does not fall back to the legacy Boolean',
      () async {
        SharedPreferences.setMockInitialValues({
          SessionStorageKeys.isLoggedIn: true,
        });
        final fakeStore = FakeSecureKeyValueStore()
          ..readError = Exception('simulated Keystore read failure');

        final result = await resolveStartupSession(serviceOver(fakeStore));

        expect(result.isLoggedIn, isFalse);
      },
    );
  });
}
