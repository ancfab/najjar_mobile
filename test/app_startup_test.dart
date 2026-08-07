// Tests for MyApp's startup auth gate: given the persisted-session state
// main() resolves before calling runApp, does the app open on Login or on
// an authenticated screen? This is what stops a relaunch after logout — or
// after the ANC API has revoked the token server-side — from reopening on
// Home (or any other authenticated screen).
//
// Also covers resolveStartupSession directly — the pure function that
// decides that state from AuthService.confirmSession, which itself calls
// `GET /auth/me` — against a real AuthService wired to a recording fake
// http.Client (never the live ANC API) and a real SecureAuthSessionStore
// wired to a fake in-memory SecureKeyValueStore (never a real
// Keychain/Keystore platform channel). Proves the
// valid/missing/corrupted/legacy-Boolean/storage-failure/revoked/malformed/
// network-failure cases all resolve safely, that a storage failure never
// falls back to the legacy Boolean, and that a stored token is never
// trusted without a successful /auth/me confirmation.
//
// All identifiers below (username, phone, token, bc_customer_no) are
// synthetic fixtures, not real or supplied backend test-account values.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/config/api_config.dart';
import 'package:anc_fabrics/main.dart';
import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/secure_auth_session_store.dart';
import 'package:anc_fabrics/services/session_messages.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';

import 'helpers/fake_secure_key_value_store.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';
const _sessionKey = 'anc_auth_session_v1';

AuthSession _validSession({String username = 'sample.user'}) => AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: username,
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

/// Records the single request it receives and replies with a canned
/// response (or throws, to simulate a transport failure), so tests can
/// assert on exactly what confirmSession sent without making a real network
/// call. Mirrors the fixture in anc_api_client_test.dart/auth_service_test.dart.
class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  http.Request? lastRequest;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    lastRequest = req;
    requestCount++;
    return _respond(req);
  }

  @override
  void close() {}
}

/// An http.Client that fails the test if it is ever called — used for
/// scenarios where no valid local session exists, so `/auth/me` must never
/// be reached.
_RecordingHttpClient _shouldNeverBeCalledHttpClient() =>
    _RecordingHttpClient((req) async {
      throw StateError(
        'confirmSession must not call the ANC API without a stored session.',
      );
    });

http.StreamedResponse _meSuccessResponse(
  http.Request request, {
  String username = 'sample.user',
  String? avatarUrl,
}) {
  final body = jsonEncode({
    'data': {
      'id': 7,
      'username': username,
      'phone': '+96890000000',
      'country': 'OM',
      'client_id': ApiConfig.clientId,
      'bc_customer_no': 'SAMPLE-0001',
      'must_change_password': false,
      'avatar_url': avatarUrl,
    },
  });
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

http.StreamedResponse _meStatusResponse(http.Request request, int statusCode) {
  return http.StreamedResponse(
    Stream.value(utf8.encode('{}')),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Defaults to Login when constructed without an explicit session state '
    '(matches a fresh, logged-out install)',
    (tester) async {
      await tester.pumpWidget(MyApp());
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets(
    'Opens on Login when the startup session check reports logged out '
    '(e.g. after logout cleared the session, or a stored token was revoked)',
    (tester) async {
      await tester.pumpWidget(MyApp(isLoggedIn: false));
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets('Opens on Home when the startup session check reports an active '
      'session', (tester) async {
    await tester.pumpWidget(MyApp(isLoggedIn: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('Shows the startup message once on Login after a secure-session '
      'restore failure', (tester) async {
    const message =
        'We could not restore your secure session. Please sign in again.';

    await tester.pumpWidget(
      MyApp(
        isLoggedIn: false,
        startupMessage: LoginStartupMessage.restoreFailed,
      ),
    );
    await tester.pump(); // let the post-frame callback fire
    await tester.pump(); // let the SnackBar animate in

    expect(find.text(message), findsOneWidget);
  });

  testWidgets('Shows no startup message when none is supplied', (tester) async {
    await tester.pumpWidget(MyApp(isLoggedIn: false));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  group('resolveStartupSession', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    AuthService serviceOver(
      FakeSecureKeyValueStore fakeStore,
      _RecordingHttpClient httpClient,
    ) => AuthService(
      apiClient: AncApiClient(httpClient: httpClient),
      sessionStore: SecureAuthSessionStore(secureStore: fakeStore),
    );

    test(
      'a valid secure session confirmed by /auth/me resolves isLoggedIn true',
      () async {
        final fakeStore = FakeSecureKeyValueStore();
        await SecureAuthSessionStore(
          secureStore: fakeStore,
        ).save(_validSession());
        final fakeHttp = _RecordingHttpClient(
          (req) async => _meSuccessResponse(req),
        );

        final result = await resolveStartupSession(
          serviceOver(fakeStore, fakeHttp),
        );

        expect(result.isLoggedIn, isTrue);
        expect(result.startupMessage, isNull);
        expect(result.sessionInvalidated, isFalse);
        expect(
          result.avatarUrl,
          isNull,
          reason: 'the confirmed /auth/me response here has no avatar_url',
        );
      },
    );

    test(
      'a valid session with a confirmed avatar_url surfaces it on the '
      'startup result, for main() to hand to CurrentUserAvatarController',
      () async {
        final fakeStore = FakeSecureKeyValueStore();
        await SecureAuthSessionStore(
          secureStore: fakeStore,
        ).save(_validSession());
        final fakeHttp = _RecordingHttpClient(
          (req) async => _meSuccessResponse(
            req,
            avatarUrl: 'https://cdn.example.com/avatars/7.jpg',
          ),
        );

        final result = await resolveStartupSession(
          serviceOver(fakeStore, fakeHttp),
        );

        expect(result.isLoggedIn, isTrue);
        expect(result.avatarUrl, 'https://cdn.example.com/avatars/7.jpg');
      },
    );

    test('a session-invalidated outcome (401/malformed) never carries an '
        'avatarUrl', () async {
      final fakeStore = FakeSecureKeyValueStore();
      await SecureAuthSessionStore(
        secureStore: fakeStore,
      ).save(_validSession());
      final fakeHttp = _RecordingHttpClient(
        (req) async => _meStatusResponse(req, 401),
      );

      final result = await resolveStartupSession(
        serviceOver(fakeStore, fakeHttp),
      );

      expect(result.sessionInvalidated, isTrue);
      expect(result.avatarUrl, isNull);
    });

    test(
      'confirming a valid session sends Authorization: Bearer <storedToken>',
      () async {
        final fakeStore = FakeSecureKeyValueStore();
        await SecureAuthSessionStore(
          secureStore: fakeStore,
        ).save(_validSession());
        final fakeHttp = _RecordingHttpClient(
          (req) async => _meSuccessResponse(req),
        );

        await resolveStartupSession(serviceOver(fakeStore, fakeHttp));

        expect(
          fakeHttp.lastRequest!.headers['Authorization'],
          'Bearer $_syntheticToken',
        );
        expect(fakeHttp.lastRequest!.headers['Accept'], 'application/json');
      },
    );

    test(
      'HomeScreen is not reachable until the /auth/me call completes',
      () async {
        final fakeStore = FakeSecureKeyValueStore();
        await SecureAuthSessionStore(
          secureStore: fakeStore,
        ).save(_validSession());
        final completer = Completer<http.StreamedResponse>();
        final fakeHttp = _RecordingHttpClient((req) => completer.future);

        var resolved = false;
        final future = resolveStartupSession(serviceOver(fakeStore, fakeHttp))
            .then((result) {
              resolved = true;
              return result;
            });

        await Future<void>.delayed(Duration.zero);
        expect(
          resolved,
          isFalse,
          reason:
              'the startup gate must not resolve isLoggedIn before /auth/me '
              'answers',
        );

        completer.complete(_meSuccessResponse(fakeHttp.lastRequest!));
        final result = await future;

        expect(resolved, isTrue);
        expect(result.isLoggedIn, isTrue);
      },
    );

    test('no secure session resolves isLoggedIn false without calling the '
        'ANC API', () async {
      final fakeHttp = _shouldNeverBeCalledHttpClient();

      final result = await resolveStartupSession(
        serviceOver(FakeSecureKeyValueStore(), fakeHttp),
      );

      expect(result.isLoggedIn, isFalse);
      expect(result.startupMessage, isNull);
      expect(fakeHttp.requestCount, 0);
    });

    test('the legacy Boolean alone resolves isLoggedIn false', () async {
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
      });
      final fakeHttp = _shouldNeverBeCalledHttpClient();

      final result = await resolveStartupSession(
        serviceOver(FakeSecureKeyValueStore(), fakeHttp),
      );

      expect(result.isLoggedIn, isFalse);
    });

    test('a corrupted secure session resolves isLoggedIn false without calling '
        'the ANC API', () async {
      final fakeStore = FakeSecureKeyValueStore()
        ..seed(_sessionKey, 'not json at all');
      final fakeHttp = _shouldNeverBeCalledHttpClient();

      final result = await resolveStartupSession(
        serviceOver(fakeStore, fakeHttp),
      );

      expect(result.isLoggedIn, isFalse);
    });

    test(
      'an unsupported secure-session schema resolves isLoggedIn false',
      () async {
        final json = _validSession().toJson()..['schema_version'] = 2;
        final fakeStore = FakeSecureKeyValueStore()
          ..seed(_sessionKey, jsonEncode(json));
        final fakeHttp = _shouldNeverBeCalledHttpClient();

        final result = await resolveStartupSession(
          serviceOver(fakeStore, fakeHttp),
        );

        expect(result.isLoggedIn, isFalse);
      },
    );

    test('a secure-storage read failure does not crash startup and returns a '
        'safe message', () async {
      final fakeStore = FakeSecureKeyValueStore()
        ..readError = Exception('simulated Keystore read failure');
      final fakeHttp = _shouldNeverBeCalledHttpClient();

      final result = await resolveStartupSession(
        serviceOver(fakeStore, fakeHttp),
      );

      expect(result.isLoggedIn, isFalse);
      // A typed reason (never a raw formatted string) so it can never leak
      // a storage implementation detail like "Keystore".
      expect(result.startupMessage, LoginStartupMessage.restoreFailed);
      expect(result.sessionInvalidated, isFalse);
    });

    test(
      'a secure-storage failure does not fall back to the legacy Boolean',
      () async {
        SharedPreferences.setMockInitialValues({
          SessionStorageKeys.isLoggedIn: true,
        });
        final fakeStore = FakeSecureKeyValueStore()
          ..readError = Exception('simulated Keystore read failure');
        final fakeHttp = _shouldNeverBeCalledHttpClient();

        final result = await resolveStartupSession(
          serviceOver(fakeStore, fakeHttp),
        );

        expect(result.isLoggedIn, isFalse);
      },
    );

    test(
      'a stored token rejected by /auth/me with HTTP 401 resolves isLoggedIn '
      'false and clears the secure session',
      () async {
        final fakeStore = FakeSecureKeyValueStore();
        final sessionStore = SecureAuthSessionStore(secureStore: fakeStore);
        await sessionStore.save(_validSession());
        final fakeHttp = _RecordingHttpClient(
          (req) async => _meStatusResponse(req, 401),
        );

        final result = await resolveStartupSession(
          serviceOver(fakeStore, fakeHttp),
        );

        expect(result.isLoggedIn, isFalse);
        expect(result.startupMessage, isNotNull);
        expect(result.sessionInvalidated, isTrue);
        expect(await sessionStore.read(), isNull);
      },
    );

    test('a malformed /auth/me response resolves isLoggedIn false and clears '
        'the secure session (never treated as still valid)', () async {
      final fakeStore = FakeSecureKeyValueStore();
      final sessionStore = SecureAuthSessionStore(secureStore: fakeStore);
      await sessionStore.save(_validSession());
      final fakeHttp = _RecordingHttpClient(
        // A 200 body missing the required "data" wrapper.
        (req) async => http.StreamedResponse(
          Stream.value(utf8.encode('{}')),
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        ),
      );

      final result = await resolveStartupSession(
        serviceOver(fakeStore, fakeHttp),
      );

      expect(result.isLoggedIn, isFalse);
      expect(result.sessionInvalidated, isTrue);
      expect(await sessionStore.read(), isNull);
    });

    test('a network failure while confirming an existing session is not '
        'treated as invalid credentials: Login is shown but the secure '
        'session is left intact for a later retry', () async {
      final fakeStore = FakeSecureKeyValueStore();
      final sessionStore = SecureAuthSessionStore(secureStore: fakeStore);
      await sessionStore.save(_validSession());
      final fakeHttp = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );

      final result = await resolveStartupSession(
        serviceOver(fakeStore, fakeHttp),
      );

      expect(result.isLoggedIn, isFalse);
      expect(result.startupMessage, isNotNull);
      expect(
        result.sessionInvalidated,
        isFalse,
        reason:
            'a network failure must not be treated as a revoked '
            'session',
      );
      expect(
        await sessionStore.read(),
        isNotNull,
        reason:
            'the secure session must survive a transient network '
            'failure so a later launch with connectivity can still '
            'succeed',
      );
    });

    test('the /auth/me-confirmed session replaces stale locally cached '
        'identity fields', () async {
      final fakeStore = FakeSecureKeyValueStore();
      final sessionStore = SecureAuthSessionStore(secureStore: fakeStore);
      await sessionStore.save(_validSession(username: 'stale.name'));
      final fakeHttp = _RecordingHttpClient(
        (req) async => _meSuccessResponse(req, username: 'fresh.name'),
      );

      await resolveStartupSession(serviceOver(fakeStore, fakeHttp));

      final persisted = await sessionStore.read();
      expect(persisted!.username, 'fresh.name');
      expect(
        persisted.token,
        _syntheticToken,
        reason: '/auth/me never returns a new token',
      );
    });

    test('confirming session state makes at most one HTTP request (no retry '
        'loop / duplicate redirect trigger)', () async {
      final fakeStore = FakeSecureKeyValueStore();
      await SecureAuthSessionStore(
        secureStore: fakeStore,
      ).save(_validSession());
      final fakeHttp = _RecordingHttpClient(
        (req) async => _meStatusResponse(req, 401),
      );

      await resolveStartupSession(serviceOver(fakeStore, fakeHttp));

      expect(fakeHttp.requestCount, 1);
    });
  });
}
