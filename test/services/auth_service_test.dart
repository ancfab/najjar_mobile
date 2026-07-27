// Unit tests for AuthService against a real AncApiClient wired to a
// recording fake http.Client (never the live ANC API) and a fake in-memory
// AuthSessionStore (never real Keychain/Keystore). Covers login request
// construction and input normalization, the success/session-persistence
// flow, the HTTP 422/5xx/network/protocol/secure-storage failure taxonomy,
// input-defensive checks, exception-boundary behavior for programmer
// errors, and AncApiClient ownership.
//
// All identifiers below (username, phone, token, bc_customer_no, password)
// are synthetic fixtures, not real or supplied backend test-account values.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/config/api_config.dart';
import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/auth/login_failure.dart';
import 'package:anc_fabrics/models/auth/session_validation_result.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/session_storage_exception.dart';

import '../helpers/fake_auth_session_store.dart';

/// Records the single request it receives and replies with a canned
/// response (or throws, to simulate a transport failure), so tests can
/// assert on exactly what AuthService sent without making a real network
/// call. Mirrors the fixture in anc_api_client_test.dart.
class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  http.Request? lastRequest;
  int requestCount = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    lastRequest = req;
    requestCount++;
    return _respond(req);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.StreamedResponse _jsonResponse(
  int statusCode,
  Map<String, dynamic> body, {
  required http.Request request,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

http.StreamedResponse _rawResponse(
  int statusCode,
  String body, {
  required http.Request request,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    request: request,
  );
}

const _validCountry = 'OM';
const _validPhone = '+96890000000';
const _validUsername = 'sample.user';
const _validPassword = 'synthetic-test-password';
const _syntheticToken = 'synthetic-id|synthetic-secret';

Map<String, dynamic> _validUserJson({bool mustChangePassword = false}) => {
  'id': 7,
  'username': _validUsername,
  'phone': _validPhone,
  'country': _validCountry,
  'client_id': ApiConfig.clientId,
  'bc_customer_no': 'SAMPLE-0001',
  'must_change_password': mustChangePassword,
};

Map<String, dynamic> _validLoginResponseJson({
  String token = _syntheticToken,
  bool topLevelMustChangePassword = false,
  bool userMustChangePassword = false,
}) => {
  'token': token,
  'must_change_password': topLevelMustChangePassword,
  'user': _validUserJson(mustChangePassword: userMustChangePassword),
};

_RecordingHttpClient _successHttpClient({String token = _syntheticToken}) =>
    _RecordingHttpClient(
      (req) async => _jsonResponse(
        200,
        _validLoginResponseJson(token: token),
        request: req,
      ),
    );

_RecordingHttpClient _validationFailureHttpClient(Map<String, dynamic> body) =>
    _RecordingHttpClient((req) async => _jsonResponse(422, body, request: req));

_RecordingHttpClient _neverRespondingHttpClient() =>
    _RecordingHttpClient((req) => Completer<http.StreamedResponse>().future);

AuthService _service(
  _RecordingHttpClient httpClient,
  FakeAuthSessionStore store, {
  Duration requestTimeout = const Duration(seconds: 15),
}) => AuthService(
  apiClient: AncApiClient(
    httpClient: httpClient,
    requestTimeout: requestTimeout,
  ),
  sessionStore: store,
);

void main() {
  late FakeAuthSessionStore store;

  setUp(() {
    store = FakeAuthSessionStore();
  });

  group('successful login: request construction', () {
    test('supplies ApiConfig.clientId, never a caller value', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      final sentBody =
          jsonDecode(http.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody['client_id'], ApiConfig.clientId);
    });

    test('sends country exactly after trimming outer whitespace', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      await service.login(
        country: '  $_validCountry  ',
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      final sentBody =
          jsonDecode(http.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody['country'], _validCountry);
    });

    test('sends phone exactly, without trimming', () async {
      final http = _successHttpClient();
      final service = _service(http, store);
      const phoneWithOuterSpace = ' $_validPhone';

      await service.login(
        country: _validCountry,
        phone: phoneWithOuterSpace,
        username: _validUsername,
        password: _validPassword,
      );

      final sentBody =
          jsonDecode(http.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody['phone'], phoneWithOuterSpace);
    });

    test('trims username outer whitespace', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: '  $_validUsername  ',
        password: _validPassword,
      );

      final sentBody =
          jsonDecode(http.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody['username'], _validUsername);
    });

    test(
      'preserves password exactly, including intentional leading/trailing spaces',
      () async {
        final http = _successHttpClient();
        final service = _service(http, store);
        const spacedPassword = '  $_validPassword  ';

        await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: spacedPassword,
        );

        final sentBody =
            jsonDecode(http.lastRequest!.body) as Map<String, dynamic>;
        expect(sentBody['password'], spacedPassword);
      },
    );

    test('calls AncApiClient login exactly once', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(http.requestCount, 1);
    });
  });

  group('successful login: session mapping and persistence', () {
    test('maps LoginResponse into the persisted AuthSession', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      final success = result as AuthLoginSuccess;
      expect(success.session.userId, 7);
      expect(success.session.username, _validUsername);
      expect(success.session.phone, _validPhone);
      expect(success.session.country, _validCountry);
      expect(success.session.clientId, ApiConfig.clientId);
      expect(success.session.bcCustomerNo, 'SAMPLE-0001');
    });

    test('preserves the token byte-for-byte', () async {
      const rawToken = '1|abcDEF1234567890ExampleOpaqueValue';
      final http = _successHttpClient(token: rawToken);
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect((result as AuthLoginSuccess).session.token, rawToken);
    });

    test(
      'persists the normalized top-level mustChangePassword value',
      () async {
        final http = _RecordingHttpClient(
          (req) async => _jsonResponse(
            200,
            _validLoginResponseJson(
              topLevelMustChangePassword: true,
              userMustChangePassword: false,
            ),
            request: req,
          ),
        );
        final service = _service(http, store);

        final result = await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: _validPassword,
        );

        expect((result as AuthLoginSuccess).session.mustChangePassword, isTrue);
      },
    );

    test('saves the session exactly once', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(store.saveCallCount, 1);
    });

    test('returns success only after the session save completes', () async {
      final completer = Completer<void>();
      store.saveGate = completer.future;
      final http = _successHttpClient();
      final service = _service(http, store);

      var completed = false;
      final future = service
          .login(
            country: _validCountry,
            phone: _validPhone,
            username: _validUsername,
            password: _validPassword,
          )
          .then((result) {
            completed = true;
            return result;
          });

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse, reason: 'save has not resolved yet');

      completer.complete();
      final result = await future;

      expect(completed, isTrue);
      expect(result, isA<AuthLoginSuccess>());
    });

    test('success toString does not expose the token or password', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(result.toString(), isNot(contains(_syntheticToken)));
      expect(result.toString(), isNot(contains(_validPassword)));
    });
  });

  group('session save behavior', () {
    test('no session save occurs when the API login fails', () async {
      final http = _validationFailureHttpClient({
        'message': 'The given data was invalid.',
        'errors': {
          'username': ['These credentials do not match our records.'],
        },
      });
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(store.saveCallCount, 0);
    });

    test(
      'a storage failure after HTTP success becomes a secureStorage failure',
      () async {
        store.saveError = const SessionStorageException(
          SessionStorageOperation.write,
        );
        final http = _successHttpClient();
        final service = _service(http, store);

        final result = await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: _validPassword,
        );

        expect(result, isA<AuthLoginFailure>());
        expect(
          (result as AuthLoginFailure).type,
          AuthLoginFailureType.secureStorage,
        );
      },
    );

    test('a storage failure never returns success', () async {
      store.saveError = const SessionStorageException(
        SessionStorageOperation.write,
      );
      final http = _successHttpClient();
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(result, isNot(isA<AuthLoginSuccess>()));
    });

    test(
      'login never clears the session store (no legacy Boolean path)',
      () async {
        final http = _successHttpClient();
        final service = _service(http, store);

        await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: _validPassword,
        );

        expect(store.clearCallCount, 0);
      },
    );

    test('the persisted session never carries a password field', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      final persistedJson = store.savedSessions.single.toJson();
      expect(persistedJson.containsKey('password'), isFalse);
      expect(jsonEncode(persistedJson), isNot(contains(_validPassword)));
    });
  });

  group('HTTP 422 mapping', () {
    test('errors.phone maps to invalidPhone', () async {
      final http = _validationFailureHttpClient({
        'message': 'The given data was invalid.',
        'errors': {
          'phone': ['The phone field format is invalid.'],
        },
      });
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidPhone,
      );
    });

    test('retains the first errors.phone message safely', () async {
      final http = _validationFailureHttpClient({
        'errors': {
          'phone': ['The phone field format is invalid.', 'A second message.'],
        },
      });
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).phoneError,
        'The phone field format is invalid.',
      );
    });

    test('errors.username maps to invalidCredentials', () async {
      final http = _validationFailureHttpClient({
        'errors': {
          'username': ['These credentials do not match our records.'],
        },
      });
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidCredentials,
      );
    });

    test('an unknown validation key maps neutrally', () async {
      final http = _validationFailureHttpClient({
        'errors': {
          'some_unexpected_field': ['Unexpected.'],
        },
      });
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidCredentials,
      );
    });

    test('an empty errors object maps neutrally', () async {
      final http = _validationFailureHttpClient({
        'message': 'The given data was invalid.',
        'errors': <String, dynamic>{},
      });
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidCredentials,
      );
    });

    test('a malformed (non-JSON) validation body maps neutrally', () async {
      final http = _RecordingHttpClient(
        (req) async => _rawResponse(422, 'not json at all', request: req),
      );
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidCredentials,
      );
    });

    test(
      'the raw credential message is not exposed as a username/password proof',
      () async {
        const rawMessage = 'These credentials do not match our records.';
        final http = _validationFailureHttpClient({
          'errors': {
            'username': [rawMessage],
          },
        });
        final service = _service(http, store);

        final result = await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: _validPassword,
        );

        final failure = result as AuthLoginFailure;
        expect(failure.phoneError, isNull);
        expect(failure.toString(), isNot(contains(rawMessage)));
      },
    );
  });

  group('transport, protocol, and other HTTP mapping', () {
    test('a timeout maps to network', () async {
      final http = _neverRespondingHttpClient();
      final service = _service(
        http,
        store,
        requestTimeout: const Duration(milliseconds: 20),
      );

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect((result as AuthLoginFailure).type, AuthLoginFailureType.network);
    });

    test('HTTP 500 maps to serviceUnavailable', () async {
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(500, {
          'message': 'Internal detail that should not leak',
        }, request: req),
      );
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.serviceUnavailable,
      );
    });

    test('a malformed successful response maps to invalidResponse', () async {
      final http = _RecordingHttpClient(
        (req) async => _rawResponse(200, 'not json at all', request: req),
      );
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidResponse,
      );
    });

    test(
      'an unexpected 404 status maps deterministically to serviceUnavailable',
      () async {
        final http = _RecordingHttpClient(
          (req) async => _jsonResponse(404, const {}, request: req),
        );
        final service = _service(http, store);

        final result = await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: _validPassword,
        );

        expect(
          (result as AuthLoginFailure).type,
          AuthLoginFailureType.serviceUnavailable,
        );
      },
    );

    test(
      'an unexpected 401 maps neutrally and does not clear the session store',
      () async {
        final http = _RecordingHttpClient(
          (req) async => _jsonResponse(401, const {}, request: req),
        );
        final service = _service(http, store);

        final result = await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: _validPassword,
        );

        expect(
          (result as AuthLoginFailure).type,
          AuthLoginFailureType.serviceUnavailable,
        );
        expect(store.clearCallCount, 0);
        expect(store.saveCallCount, 0);
      },
    );

    test('no retry occurs after a failure', () async {
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(500, const {}, request: req),
      );
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(http.requestCount, 1);
    });
  });

  group('input handling', () {
    test('empty country returns invalidInput without an HTTP call', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      final result = await service.login(
        country: '   ',
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidInput,
      );
      expect(http.requestCount, 0);
    });

    test('empty phone returns invalidInput without an HTTP call', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: '',
        username: _validUsername,
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidInput,
      );
      expect(http.requestCount, 0);
    });

    test('empty username returns invalidInput without an HTTP call', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: '   ',
        password: _validPassword,
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidInput,
      );
      expect(http.requestCount, 0);
    });

    test('empty password returns invalidInput without an HTTP call', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      final result = await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: '',
      );

      expect(
        (result as AuthLoginFailure).type,
        AuthLoginFailureType.invalidInput,
      );
      expect(http.requestCount, 0);
    });

    test(
      'a whitespace-only password is not treated as empty and is sent unchanged',
      () async {
        final http = _successHttpClient();
        final service = _service(http, store);
        const whitespacePassword = '   ';

        await service.login(
          country: _validCountry,
          phone: _validPhone,
          username: _validUsername,
          password: whitespacePassword,
        );

        final sentBody =
            jsonDecode(http.lastRequest!.body) as Map<String, dynamic>;
        expect(sentBody['password'], whitespacePassword);
      },
    );

    test('the caller cannot override clientId', () async {
      final http = _successHttpClient();
      final service = _service(http, store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );

      final sentBody =
          jsonDecode(http.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody['client_id'], ApiConfig.clientId);
      expect(sentBody.containsKey('clientId'), isFalse);
    });
  });

  group('exception boundary behavior', () {
    test(
      'an injected StateError propagates unchanged, not as a failure',
      () async {
        final http = _RecordingHttpClient(
          (req) async => throw StateError('simulated bug in a test double'),
        );
        final service = _service(http, store);

        await expectLater(
          service.login(
            country: _validCountry,
            phone: _validPhone,
            username: _validUsername,
            password: _validPassword,
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'no failure toString contains the password, token, or raw response',
      () async {
        const rawMessage = 'These credentials do not match our records.';
        final scenarios = <_RecordingHttpClient>[
          _validationFailureHttpClient({
            'errors': {
              'username': [rawMessage],
            },
          }),
          _RecordingHttpClient(
            (req) async => _jsonResponse(500, {
              'message': 'Internal detail',
            }, request: req),
          ),
          _RecordingHttpClient(
            (req) async => _rawResponse(200, 'not json at all', request: req),
          ),
        ];

        for (final http in scenarios) {
          final service = _service(http, store);
          final result = await service.login(
            country: _validCountry,
            phone: _validPhone,
            username: _validUsername,
            password: _validPassword,
          );

          expect(result.toString(), isNot(contains(_validPassword)));
          expect(result.toString(), isNot(contains(_syntheticToken)));
          expect(result.toString(), isNot(contains(rawMessage)));
        }
      },
    );
  });

  group('AncApiClient ownership', () {
    test('does not close a caller-supplied AncApiClient', () async {
      final http = _successHttpClient();
      final apiClient = AncApiClient(httpClient: http);
      final service = AuthService(apiClient: apiClient, sessionStore: store);

      await service.login(
        country: _validCountry,
        phone: _validPhone,
        username: _validUsername,
        password: _validPassword,
      );
      service.close();

      expect(http.closed, isFalse);
    });

    test('a production-owned client can be closed safely', () {
      final service = AuthService.production(sessionStore: store);

      expect(service.close, returnsNormally);
    });

    test('close is idempotent', () {
      final service = AuthService.production(sessionStore: store);

      service.close();

      expect(service.close, returnsNormally);
    });
  });

  group('confirmSession', () {
    const storedToken = 'synthetic-id|synthetic-secret';

    AuthSession storedSession({String username = _validUsername}) =>
        AuthSession(
          token: storedToken,
          userId: 7,
          username: username,
          phone: _validPhone,
          country: _validCountry,
          clientId: ApiConfig.clientId,
          bcCustomerNo: 'SAMPLE-0001',
          mustChangePassword: false,
        );

    Map<String, dynamic> meUserJson({
      String username = 'refreshed.user',
      bool mustChangePassword = false,
    }) => {
      'id': 7,
      'username': username,
      'phone': _validPhone,
      'country': _validCountry,
      'client_id': ApiConfig.clientId,
      'bc_customer_no': 'SAMPLE-0001',
      'must_change_password': mustChangePassword,
    };

    _RecordingHttpClient meSuccessHttpClient({
      String username = 'refreshed.user',
    }) => _RecordingHttpClient(
      (req) async => _jsonResponse(200, {
        'data': meUserJson(username: username),
      }, request: req),
    );

    test('no stored session resolves to SessionValidationAbsent', () async {
      final http = meSuccessHttpClient();
      final service = _service(http, store);

      final result = await service.confirmSession();

      expect(result, isA<SessionValidationAbsent>());
      expect(http.requestCount, 0);
    });

    test(
      'a secure-storage read failure resolves to SessionValidationStorageFailure',
      () async {
        store.readError = const SessionStorageException(
          SessionStorageOperation.read,
        );
        final http = meSuccessHttpClient();
        final service = _service(http, store);

        final result = await service.confirmSession();

        expect(result, isA<SessionValidationStorageFailure>());
        expect(http.requestCount, 0);
      },
    );

    test('sends Authorization: Bearer <storedToken> to /auth/me', () async {
      store.seed(storedSession());
      final http = meSuccessHttpClient();
      final service = _service(http, store);

      await service.confirmSession();

      expect(http.lastRequest!.headers['Authorization'], 'Bearer $storedToken');
      expect(
        http.lastRequest!.url,
        Uri.parse('https://api.ancfab.com/api/auth/me'),
      );
    });

    test('HTTP 200 resolves to SessionValidationValid with the refreshed user '
        'and the original token preserved', () async {
      store.seed(storedSession(username: 'stale.name'));
      final http = meSuccessHttpClient(username: 'fresh.name');
      final service = _service(http, store);

      final result = await service.confirmSession();

      final valid = result as SessionValidationValid;
      expect(valid.session.username, 'fresh.name');
      expect(valid.session.token, storedToken);
    });

    test('HTTP 200 re-persists the refreshed session exactly once', () async {
      store.seed(storedSession(username: 'stale.name'));
      final http = meSuccessHttpClient(username: 'fresh.name');
      final service = _service(http, store);

      await service.confirmSession();

      expect(store.saveCallCount, 1);
      expect(store.savedSessions.single.username, 'fresh.name');
    });

    test('a re-persist failure after a valid /auth/me response still returns '
        'SessionValidationValid', () async {
      store.seed(storedSession());
      store.saveError = const SessionStorageException(
        SessionStorageOperation.write,
      );
      final http = meSuccessHttpClient();
      final service = _service(http, store);

      final result = await service.confirmSession();

      expect(result, isA<SessionValidationValid>());
    });

    test(
      'HTTP 401 resolves to SessionValidationRevoked and clears the store',
      () async {
        store.seed(storedSession());
        final http = _RecordingHttpClient(
          (req) async => _jsonResponse(401, const {}, request: req),
        );
        final service = _service(http, store);

        final result = await service.confirmSession();

        expect(result, isA<SessionValidationRevoked>());
        expect(store.clearCallCount, 1);
      },
    );

    test('a clear failure after HTTP 401 still resolves to '
        'SessionValidationRevoked', () async {
      store.seed(storedSession());
      store.clearError = const SessionStorageException(
        SessionStorageOperation.clear,
      );
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final service = _service(http, store);

      final result = await service.confirmSession();

      expect(result, isA<SessionValidationRevoked>());
    });

    test('a malformed /auth/me body resolves to SessionValidationUnusable and '
        'clears the store', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, meUserJson(), request: req), // no data wrapper
      );
      final service = _service(http, store);

      final result = await service.confirmSession();

      expect(result, isA<SessionValidationUnusable>());
      expect(store.clearCallCount, 1);
    });

    test('a network failure resolves to SessionValidationUnavailable and does '
        'not clear the store', () async {
      store.seed(storedSession());
      final http = _neverRespondingHttpClient();
      final service = _service(
        http,
        store,
        requestTimeout: const Duration(milliseconds: 20),
      );

      final result = await service.confirmSession();

      expect(result, isA<SessionValidationUnavailable>());
      expect(store.clearCallCount, 0);
      expect(await store.read(), isNotNull);
    });

    test('HTTP 500 resolves to SessionValidationUnavailable and does not clear '
        'the store', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(500, const {}, request: req),
      );
      final service = _service(http, store);

      final result = await service.confirmSession();

      expect(result, isA<SessionValidationUnavailable>());
      expect(store.clearCallCount, 0);
    });

    test('confirmSession makes at most one HTTP request', () async {
      store.seed(storedSession());
      final http = meSuccessHttpClient();
      final service = _service(http, store);

      await service.confirmSession();

      expect(http.requestCount, 1);
    });

    test(
      'the resolved session never exposes the token through toString',
      () async {
        store.seed(storedSession());
        final http = meSuccessHttpClient();
        final service = _service(http, store);

        final result = await service.confirmSession() as SessionValidationValid;

        expect(result.session.toString(), isNot(contains(storedToken)));
      },
    );
  });

  group('logout', () {
    const storedToken = 'synthetic-id|synthetic-secret';

    AuthSession storedSession() => const AuthSession(
      token: storedToken,
      userId: 7,
      username: _validUsername,
      phone: _validPhone,
      country: _validCountry,
      clientId: 'ANCNAJJAR',
      bcCustomerNo: 'SAMPLE-0001',
      mustChangePassword: false,
    );

    _RecordingHttpClient loggedOutHttpClient() => _RecordingHttpClient(
      (req) async =>
          _jsonResponse(200, {'message': 'Logged out.'}, request: req),
    );

    test(
      'remote 200 clears the local session and completes normally',
      () async {
        store.seed(storedSession());
        final http = loggedOutHttpClient();
        final service = _service(http, store);

        await expectLater(service.logout(), completes);
        expect(store.clearCallCount, 1);
        expect(await store.read(), isNull);
      },
    );

    test('does not clear the local session before the remote logout attempt '
        'completes (the remote call happens first)', () async {
      store.seed(storedSession());
      var sessionPresentDuringRemoteCall = false;
      final http = _RecordingHttpClient((req) async {
        sessionPresentDuringRemoteCall = await store.read() != null;
        return _jsonResponse(200, {'message': 'Logged out.'}, request: req);
      });
      final service = _service(http, store);

      await service.logout();

      expect(sessionPresentDuringRemoteCall, isTrue);
      expect(await store.read(), isNull);
    });

    test('remote 401 still clears locally and completes normally', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final service = _service(http, store);

      await expectLater(service.logout(), completes);
      expect(store.clearCallCount, 1);
      expect(await store.read(), isNull);
    });

    test('remote 422 still clears locally', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(422, const {}, request: req),
      );
      final service = _service(http, store);

      await expectLater(service.logout(), completes);
      expect(store.clearCallCount, 1);
    });

    test('remote 500 still clears locally', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(500, const {}, request: req),
      );
      final service = _service(http, store);

      await expectLater(service.logout(), completes);
      expect(store.clearCallCount, 1);
    });

    test('remote 502 still clears locally', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final service = _service(http, store);

      await expectLater(service.logout(), completes);
      expect(store.clearCallCount, 1);
    });

    test('remote 503 still clears locally', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final service = _service(http, store);

      await expectLater(service.logout(), completes);
      expect(store.clearCallCount, 1);
    });

    test('a timeout still clears locally', () async {
      store.seed(storedSession());
      final http = _neverRespondingHttpClient();
      final service = _service(
        http,
        store,
        requestTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(service.logout(), completes);
      expect(store.clearCallCount, 1);
    });

    test('a network failure still clears locally', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final service = _service(http, store);

      await expectLater(service.logout(), completes);
      expect(store.clearCallCount, 1);
    });

    test(
      'a malformed successful remote response still clears locally',
      () async {
        store.seed(storedSession());
        final http = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final service = _service(http, store);

        await expectLater(service.logout(), completes);
        expect(store.clearCallCount, 1);
      },
    );

    test(
      'missing local session skips the remote call and clears idempotently',
      () async {
        final http = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, {'message': 'Logged out.'}, request: req),
        );
        final service = _service(http, store);

        await expectLater(service.logout(), completes);
        expect(http.requestCount, 0);
        expect(store.clearCallCount, 1);
      },
    );

    test('a session read failure still attempts the local clear', () async {
      store.readError = const SessionStorageException(
        SessionStorageOperation.read,
      );
      final http = loggedOutHttpClient();
      final service = _service(http, store);

      await service.logout();

      expect(http.requestCount, 0);
      expect(store.clearCallCount, 1);
    });

    test(
      'a session read failure plus a successful clear completes normally',
      () async {
        store.readError = const SessionStorageException(
          SessionStorageOperation.read,
        );
        final http = loggedOutHttpClient();
        final service = _service(http, store);

        await expectLater(service.logout(), completes);
      },
    );

    test(
      'remote 200 plus a clear failure throws SessionStorageException',
      () async {
        store.seed(storedSession());
        store.clearError = const SessionStorageException(
          SessionStorageOperation.clear,
        );
        final http = loggedOutHttpClient();
        final service = _service(http, store);

        await expectLater(
          service.logout(),
          throwsA(isA<SessionStorageException>()),
        );
      },
    );

    test(
      'remote 502 plus a clear failure throws SessionStorageException',
      () async {
        store.seed(storedSession());
        store.clearError = const SessionStorageException(
          SessionStorageOperation.clear,
        );
        final http = _RecordingHttpClient(
          (req) async => _jsonResponse(502, const {}, request: req),
        );
        final service = _service(http, store);

        await expectLater(
          service.logout(),
          throwsA(isA<SessionStorageException>()),
        );
      },
    );

    test(
      'a read failure plus a clear failure throws the clear failure',
      () async {
        store.readError = const SessionStorageException(
          SessionStorageOperation.read,
        );
        store.clearError = const SessionStorageException(
          SessionStorageOperation.clear,
        );
        final http = loggedOutHttpClient();
        final service = _service(http, store);

        await expectLater(
          service.logout(),
          throwsA(isA<SessionStorageException>()),
        );
        expect(http.requestCount, 0);
      },
    );

    test('no automatic retry of the remote logout call', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => _jsonResponse(500, const {}, request: req),
      );
      final service = _service(http, store);

      await service.logout();

      expect(http.requestCount, 1);
    });

    test('only a local clear failure ever escapes logout() — a transport '
        'failure never does', () async {
      store.seed(storedSession());
      final http = _RecordingHttpClient(
        (req) async => throw const SocketException('a transport failure'),
      );
      final service = _service(http, store);

      await expectLater(service.logout(), completes);
    });

    test('does not import session_expiry_coordinator.dart — logout() cannot '
        'invoke SessionExpiryCoordinator because AuthService never depends on '
        'it (the class doc comment above mentions it only in prose, to '
        'explain why the two paths are deliberately kept separate)', () {
      final source = File('lib/services/auth_service.dart').readAsStringSync();

      expect(source, isNot(contains("import 'session_expiry_coordinator")));
      expect(
        source,
        isNot(contains("import '../services/session_expiry_coordinator")),
      );
    });
  });
}
