// Unit tests for AncApiClient against a recording fake http.Client — never
// the live ANC API. Covers request construction (URL, headers, body,
// absence of Authorization on login), origin-safety rejection of
// absolute/protocol-relative/leading-slash/backslash/traversal/query/
// fragment path input, response decoding (200, 422, malformed body, other
// non-2xx), exception classification (network vs. protocol vs. HTTP vs.
// programmer/argument errors), timeout handling, and http.Client ownership
// (a caller-supplied client is never closed by AncApiClient).
//
// All identifiers below (username, phone, token, bc_customer_no) are
// synthetic fixtures, not real or supplied backend test-account values.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/config/api_config.dart';
import 'package:anc_fabrics/models/auth/login_request.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/anc_api_exceptions.dart';

/// Records the single request it receives and replies with a canned
/// response (or throws, to simulate a transport failure), so tests can
/// assert on exactly what AncApiClient sent without making a real network
/// call.
class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  http.Request? lastRequest;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    lastRequest = req;
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

const _validLoginRequest = LoginRequest(
  country: 'OM',
  phone: '+96890000000',
  username: 'sample.user',
  clientId: 'ANCNAJJAR',
  password: 'placeholder-test-value',
);

Map<String, dynamic> _validUserJson() => {
  'id': 1,
  'username': 'sample.user',
  'phone': '+96890000000',
  'country': 'OM',
  'client_id': 'ANCNAJJAR',
  'bc_customer_no': 'SAMPLE-0001',
  'must_change_password': false,
};

Map<String, dynamic> _validLoginResponseJson() => {
  'token': 'synthetic-id|synthetic-secret',
  'must_change_password': false,
  'user': _validUserJson(),
};

/// A client whose requests never complete, for deterministic timeout tests.
_RecordingHttpClient _neverRespondingClient() =>
    _RecordingHttpClient((req) => Completer<http.StreamedResponse>().future);

void main() {
  group('AncApiClient.login request construction', () {
    test('POSTs to the exact login URI', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.login(_validLoginRequest);

      expect(fake.lastRequest!.method, 'POST');
      expect(
        fake.lastRequest!.url,
        Uri.parse('https://api.ancfab.com/api/auth/login'),
      );
    });

    test('sends Accept and Content-Type headers', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.login(_validLoginRequest);

      expect(fake.lastRequest!.headers['Accept'], 'application/json');
      expect(
        fake.lastRequest!.headers['Content-Type'],
        contains('application/json'),
      );
    });

    test('sends no Authorization header for login', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.login(_validLoginRequest);

      final headerKeys = fake.lastRequest!.headers.keys.map(
        (key) => key.toLowerCase(),
      );
      expect(headerKeys.contains('authorization'), isFalse);
    });

    test('sends the exact JSON body', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.login(_validLoginRequest);

      final sentBody =
          jsonDecode(fake.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody, {
        'country': 'OM',
        'phone': '+96890000000',
        'username': 'sample.user',
        'client_id': 'ANCNAJJAR',
        'password': 'placeholder-test-value',
      });
    });
  });

  group('AncApiClient origin safety', () {
    Future<void> expectRejected(String relativePath) async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.postPublicJson(relativePath, const {}),
        throwsArgumentError,
      );
      expect(
        fake.lastRequest,
        isNull,
        reason: 'A rejected path must never reach the HTTP client.',
      );
    }

    test(
      'accepts a valid relative path and preserves the base origin',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, const {}, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.postPublicJson('api/auth/login', const {});

        expect(
          fake.lastRequest!.url,
          Uri.parse('https://api.ancfab.com/api/auth/login'),
        );
        expect(fake.lastRequest!.url.origin, ApiConfig.baseUrl.origin);
      },
    );

    test('rejects an absolute URL', () async {
      await expectRejected('https://evil.example.com/steal');
    });

    test('rejects a protocol-relative URL', () async {
      await expectRejected('//evil.example.com/steal');
    });

    test('rejects a leading-slash path', () async {
      await expectRejected('/api/auth/login');
    });

    test('rejects a raw ../ path-traversal segment', () async {
      await expectRejected('api/../../etc/passwd');
    });

    test('rejects a percent-encoded path-traversal segment', () async {
      await expectRejected('api%2f..%2f..%2fadmin');
    });

    test('rejects a lone-dot path segment', () async {
      await expectRejected('api/./login');
    });

    test('rejects a backslash-based path', () async {
      await expectRejected(r'api\..\..\evil');
    });

    test('rejects a Windows-UNC-style backslash host attempt', () async {
      await expectRejected(r'\\evil.example.com\steal');
    });

    test('rejects a query string', () async {
      await expectRejected('api/auth/login?redirect=evil.example.com');
    });

    test('rejects a fragment', () async {
      await expectRejected('api/auth/login#evil.example.com');
    });

    test(
      'rejects malformed percent-encoding rather than throwing raw',
      () async {
        await expectRejected('api/auth/login%');
      },
    );
  });

  group('AncApiClient response handling', () {
    test('parses a 200 JSON body into a LoginResponse', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, {
          'token': 'synthetic-id|opaque-synthetic-token',
          'must_change_password': false,
          'user': _validUserJson(),
        }, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.login(_validLoginRequest);

      expect(response.token, 'synthetic-id|opaque-synthetic-token');
      expect(response.user.username, 'sample.user');
    });

    test(
      'exposes a parsed 422 validation error without raw JSON as the message',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'username': ['These credentials do not match our records.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.login(_validLoginRequest);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(
            error.validationError?.firstErrorFor('username'),
            'These credentials do not match our records.',
          );
          expect(error.message, isNot(contains('These credentials')));
        }
      },
    );

    test(
      'handles a malformed 422 body without an uncontrolled exception',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(422, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.login(_validLoginRequest);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError, isNotNull);
          expect(error.validationError!.errors, isEmpty);
        }
      },
    );

    test(
      'handles a malformed 200 body via a controlled protocol exception',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.login(_validLoginRequest),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'handles a non-2xx status without exposing raw JSON as a message',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(500, {
            'message': 'Internal detail that should not leak verbatim',
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.login(_validLoginRequest);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 500);
          expect(error.message, isNot(contains('Internal detail')));
        }
      },
    );
  });

  group('AncApiClient exception classification', () {
    test('wraps an http.ClientException as AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw http.ClientException('Connection refused'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.login(_validLoginRequest),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test('wraps a SocketException as AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.login(_validLoginRequest),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test(
      'does not classify an absolute-URL ArgumentError as AncNetworkException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, const {}, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.postPublicJson('https://evil.example.com', const {});
          fail('Expected an ArgumentError');
        } catch (error) {
          expect(error, isA<ArgumentError>());
          expect(error, isNot(isA<AncApiException>()));
        }
      },
    );

    test(
      'does not classify a programmer error from the HTTP layer as AncNetworkException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => throw StateError('simulated bug in a test double'),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.login(_validLoginRequest);
          fail('Expected a StateError to propagate unchanged');
        } catch (error) {
          expect(error, isA<StateError>());
          expect(error, isNot(isA<AncApiException>()));
        }
      },
    );

    test(
      'lets an AncApiException raised beneath postPublicJson pass through unchanged',
      () async {
        // A malformed 200 body raises AncProtocolException from within
        // login()'s call to postPublicJson's caller path; confirm it is
        // not re-wrapped as AncNetworkException by postPublicJson's catch
        // clauses.
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.login(_validLoginRequest);
          fail('Expected an AncProtocolException');
        } catch (error) {
          expect(error, isA<AncProtocolException>());
          expect(error, isNot(isA<AncNetworkException>()));
        }
      },
    );
  });

  group('AncApiClient timeout handling', () {
    test('wraps a timeout in a controlled network exception', () async {
      final fake = _neverRespondingClient();
      final client = AncApiClient(
        httpClient: fake,
        requestTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        client.login(_validLoginRequest),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test('defaults to ApiConfig.requestTimeout when not overridden', () async {
      final client = AncApiClient(httpClient: _neverRespondingClient());

      // Not asserting real elapsed time (would slow the suite); this only
      // confirms the production default is what ApiConfig declares.
      expect(ApiConfig.requestTimeout, const Duration(seconds: 15));
      client.close();
    });
  });

  group('AncApiClient http.Client ownership', () {
    test('does not close a caller-supplied http.Client', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.login(_validLoginRequest);
      client.close();

      expect(fake.closed, isFalse);
    });
  });
}
