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
import 'package:anc_fabrics/models/business_central/business_central_inventory_entry.dart';
import 'package:anc_fabrics/models/business_central/business_central_invoice_line.dart';
import 'package:anc_fabrics/models/business_central/business_central_item.dart';
import 'package:anc_fabrics/models/business_central/ledger_entry.dart';
import 'package:anc_fabrics/models/business_central/paginated_response.dart';
import 'package:anc_fabrics/models/business_central/payment_entry.dart';
import 'package:anc_fabrics/models/business_central/sales_order_line.dart';
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

  group('AncApiClient.fetchCurrentUser request construction', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    test('GETs the exact /auth/me URI', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, {'data': _validUserJson()}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchCurrentUser(token: syntheticToken);

      expect(fake.lastRequest!.method, 'GET');
      expect(
        fake.lastRequest!.url,
        Uri.parse('https://api.ancfab.com/api/auth/me'),
      );
    });

    test('sends Authorization: Bearer <token> and Accept headers', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, {'data': _validUserJson()}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchCurrentUser(token: syntheticToken);

      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(fake.lastRequest!.headers['Accept'], 'application/json');
    });

    test('sends no request body', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, {'data': _validUserJson()}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchCurrentUser(token: syntheticToken);

      expect(fake.lastRequest!.body, isEmpty);
    });

    test(
      'an unsafe relativePath is rejected before any request is sent',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, const {}, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.getAuthenticatedJson(
            'https://evil.example.com',
            token: syntheticToken,
          ),
          throwsArgumentError,
        );
        expect(fake.lastRequest, isNull);
      },
    );
  });

  group('AncApiClient.fetchCurrentUser response handling', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    test('parses a 200 body through the required data wrapper', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, {'data': _validUserJson()}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final user = await client.fetchCurrentUser(token: syntheticToken);

      expect(user.id, 1);
      expect(user.username, 'sample.user');
      expect(user.bcCustomerNo, 'SAMPLE-0001');
    });

    test(
      'a 200 body missing the data wrapper raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, _validUserJson(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchCurrentUser(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a malformed user object under data raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, {
            'data': {'username': 'sample.user'},
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchCurrentUser(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a malformed 200 body raises AncProtocolException, not a crash',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchCurrentUser(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchCurrentUser(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test('a transport failure raises AncNetworkException, not a 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchCurrentUser(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });
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

  group('AncApiClient.fetchLedgerEntries', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    Map<String, dynamic> validEnvelope({
      List<Map<String, dynamic>>? data,
      String? nextPageUrl,
    }) => {
      'current_page': 1,
      'data': data ?? [_validLedgerEntryJson()],
      'first_page_url':
          'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
      'from': 1,
      'last_page': 1,
      'last_page_url':
          'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
      'next_page_url': nextPageUrl,
      'path': 'https://api.ancfab.com/api/business-central/ledger-entries',
      'per_page': 25,
      'prev_page_url': null,
      'to': 1,
      'total': 1,
    };

    test('GETs the exact ledger-entries URI with page and per_page', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchLedgerEntries(token: syntheticToken);

      expect(fake.lastRequest!.method, 'GET');
      expect(
        fake.lastRequest!.url,
        Uri.parse(
          'https://api.ancfab.com/api/business-central/ledger-entries'
          '?page=1&per_page=25',
        ),
      );
    });

    test(
      'sends Accept: application/json and Authorization: Bearer <token>',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchLedgerEntries(token: syntheticToken);

        expect(fake.lastRequest!.headers['Accept'], 'application/json');
        expect(
          fake.lastRequest!.headers['Authorization'],
          'Bearer $syntheticToken',
        );
      },
    );

    test('never sends a Customer_No query parameter', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchLedgerEntries(token: syntheticToken);

      expect(
        fake.lastRequest!.url.queryParameters.containsKey('Customer_No'),
        isFalse,
      );
      expect(
        fake.lastRequest!.url.queryParameters.containsKey('customer_no'),
        isFalse,
      );
    });

    test('clamps page below 1 up to 1', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchLedgerEntries(token: syntheticToken, page: 0);

      expect(fake.lastRequest!.url.queryParameters['page'], '1');
    });

    test('clamps per_page to the configured maximum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchLedgerEntries(token: syntheticToken, perPage: 9999);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '100');
    });

    test('parses a 200 body into PaginatedResponse<LedgerEntry>', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchLedgerEntries(token: syntheticToken);

      expect(response, isA<PaginatedResponse<LedgerEntry>>());
      expect(response.data, hasLength(1));
      expect(response.data.single.entryNo, 1001);
    });

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchLedgerEntries(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test(
      'a pagination 422 exposes errors.page through validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'page': ['The page field must be at least 1.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchLedgerEntries(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError?.errors.containsKey('page'), isTrue);
        }
      },
    );

    test(
      'an account-not-linked 422 exposes its message via validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'No linked Business Central customer.',
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchLedgerEntries(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(
            error.validationError?.message,
            'No linked Business Central customer.',
          );
        }
      },
    );

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchLedgerEntries(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchLedgerEntries(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test(
      'a network failure raises AncNetworkException, preserving no session state',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => throw const SocketException('No route to host'),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchLedgerEntries(token: syntheticToken),
          throwsA(isA<AncNetworkException>()),
        );
      },
    );

    test('a malformed 200 body raises AncProtocolException', () async {
      final fake = _RecordingHttpClient(
        (req) async => _rawResponse(200, 'not json at all', request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchLedgerEntries(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test(
      'a 200 body with non-array data raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope['data'] = {'not': 'an array'};
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchLedgerEntries(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );
  });

  group('AncApiClient.fetchLedgerEntriesPage', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    test('follows a trusted https next_page_url on the ANC API host', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, {
          'current_page': 2,
          'data': [_validLedgerEntryJson()],
          'first_page_url': 'https://api.ancfab.com/x?page=1',
          'from': 26,
          'last_page': 2,
          'last_page_url': 'https://api.ancfab.com/x?page=2',
          'next_page_url': null,
          'path': 'https://api.ancfab.com/x',
          'per_page': 25,
          'prev_page_url': 'https://api.ancfab.com/x?page=1',
          'to': 27,
          'total': 27,
        }, request: req),
      );
      final client = AncApiClient(httpClient: fake);
      final nextPageUrl = Uri.parse(
        'https://api.ancfab.com/api/business-central/ledger-entries?page=2',
      );

      final response = await client.fetchLedgerEntriesPage(
        token: syntheticToken,
        nextPageUrl: nextPageUrl,
      );

      expect(fake.lastRequest!.url, nextPageUrl);
      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(response.currentPage, 2);
    });

    test('rejects an untrusted next_page_url host', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchLedgerEntriesPage(
          token: syntheticToken,
          nextPageUrl: Uri.parse('https://evil.example.com/steal?page=2'),
        ),
        throwsArgumentError,
      );
      expect(
        fake.lastRequest,
        isNull,
        reason: 'An untrusted host must never receive the bearer token.',
      );
    });

    test('rejects a non-https next_page_url on the trusted host', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchLedgerEntriesPage(
          token: syntheticToken,
          nextPageUrl: Uri.parse('http://api.ancfab.com/x?page=2'),
        ),
        throwsArgumentError,
      );
      expect(fake.lastRequest, isNull);
    });
  });

  group('AncApiClient.fetchPayments', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    Map<String, dynamic> validEnvelope({
      List<Map<String, dynamic>>? data,
      int currentPage = 1,
      int lastPage = 1,
    }) => {
      'current_page': currentPage,
      'data': data ?? [_validPaymentEntryJson()],
      'first_page_url':
          'https://api.ancfab.com/api/business-central/payments?page=1',
      'from': (data ?? [_validPaymentEntryJson()]).isEmpty ? null : 1,
      'last_page': lastPage,
      'last_page_url':
          'https://api.ancfab.com/api/business-central/payments'
          '?page=$lastPage',
      'next_page_url': null,
      'path': 'https://api.ancfab.com/api/business-central/payments',
      'per_page': 25,
      'prev_page_url': null,
      'to': (data ?? [_validPaymentEntryJson()]).isEmpty ? null : 1,
      'total': (data ?? [_validPaymentEntryJson()]).length,
    };

    test('GETs the exact payments URI with page and per_page', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchPayments(token: syntheticToken);

      expect(fake.lastRequest!.method, 'GET');
      expect(
        fake.lastRequest!.url,
        Uri.parse(
          'https://api.ancfab.com/api/business-central/payments'
          '?page=1&per_page=25',
        ),
      );
    });

    test('sends Accept: application/json and Authorization: Bearer <token>, '
        'never a request body', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchPayments(token: syntheticToken);

      expect(fake.lastRequest!.headers['Accept'], 'application/json');
      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(fake.lastRequest!.body, isEmpty);
    });

    test('never sends a customerNo query or body field', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchPayments(token: syntheticToken);

      final query = fake.lastRequest!.url.queryParameters;
      expect(query.containsKey('customerNo'), isFalse);
      expect(query.containsKey('Customer_No'), isFalse);
      expect(query.containsKey('customer_no'), isFalse);
      expect(fake.lastRequest!.body, isNot(contains('customerNo')));
    });

    test('clamps page below 1 up to 1', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchPayments(token: syntheticToken, page: 0);

      expect(fake.lastRequest!.url.queryParameters['page'], '1');
    });

    test('clamps per_page to the configured maximum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchPayments(token: syntheticToken, perPage: 9999);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '100');
    });

    test('clamps per_page below the configured minimum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchPayments(token: syntheticToken, perPage: 0);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '1');
    });

    test('parses a 200 body into PaginatedResponse<PaymentEntry>', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchPayments(token: syntheticToken);

      expect(response, isA<PaginatedResponse<PaymentEntry>>());
      expect(response.data, hasLength(1));
      expect(response.data.single.entryNo, 1001);
      expect(response.data.single.documentNo, 'PAY-001');
    });

    test('parses an empty page (no rows)', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: const []), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchPayments(token: syntheticToken);

      expect(response.data, isEmpty);
      expect(response.total, 0);
    });

    test(
      'a malformed envelope (missing data) raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope.remove('data');
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchPayments(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a malformed payment row (missing entryNo) raises AncProtocolException',
      () async {
        final badRow = _validPaymentEntryJson()..remove('entryNo');
        final fake = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, validEnvelope(data: [badRow]), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchPayments(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('a payment row using Ledger-style keys (Entry_No) raises '
        'AncProtocolException rather than silently parsing', () async {
      final ledgerShapedRow = {
        'Entry_No': 1001,
        'Posting_Date': '2026-01-05',
        'Document_No': 'PAY-001',
        'Customer_No': 'CLNT-0001',
        'Customer_Name': 'Test Customer One',
        'Currency_Code': 'USD',
        'Amount': 100.50,
        'Remaining_Amount': 0.0,
        'Open': false,
        'Due_Date': '2026-01-15',
      };
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [ledgerShapedRow]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchPayments(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchPayments(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test(
      'a pagination 422 exposes errors.page through validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'page': ['The page field must be at least 1.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchPayments(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError?.errors.containsKey('page'), isTrue);
        }
      },
    );

    test(
      'an account-not-linked 422 exposes its message via validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'No linked Business Central customer.',
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchPayments(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(
            error.validationError?.message,
            'No linked Business Central customer.',
          );
        }
      },
    );

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchPayments(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchPayments(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('a network failure raises AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchPayments(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test('a malformed 200 body raises AncProtocolException', () async {
      final fake = _RecordingHttpClient(
        (req) async => _rawResponse(200, 'not json at all', request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchPayments(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test(
      'a 200 body with non-array data raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope['data'] = {'not': 'an array'};
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchPayments(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('only ever uses the synthetic test token, never a real one', () {
      expect(syntheticToken, startsWith('synthetic-'));
    });
  });

  group('AncApiClient.fetchInvoices', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    Map<String, dynamic> validEnvelope({
      List<Map<String, dynamic>>? data,
      int currentPage = 1,
      int lastPage = 1,
    }) {
      final rows = data ?? [_validInvoiceLineJson()];
      return {
        'current_page': currentPage,
        'data': rows,
        // The confirmed live envelope's URL metadata is unsafe/incomplete
        // (a bare "/?page=2" / "/") — these fixtures deliberately mirror
        // that shape so tests prove AncApiClient/InvoicesService never read
        // or follow it.
        'first_page_url': '/?page=1',
        'from': rows.isEmpty ? null : 1,
        'last_page': lastPage,
        'last_page_url': '/?page=$lastPage',
        'next_page_url': currentPage < lastPage
            ? '/?page=${currentPage + 1}'
            : null,
        'path': '/',
        'per_page': 25,
        'prev_page_url': null,
        'to': rows.isEmpty ? null : rows.length,
        'total': rows.length,
      };
    }

    test('GETs the exact invoices URI with page and per_page', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken);

      expect(fake.lastRequest!.method, 'GET');
      expect(
        fake.lastRequest!.url,
        Uri.parse(
          'https://api.ancfab.com/api/business-central/invoices'
          '?page=1&per_page=25',
        ),
      );
    });

    test('sends Accept: application/json and Authorization: Bearer <token>, '
        'never a request body', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken);

      expect(fake.lastRequest!.headers['Accept'], 'application/json');
      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(fake.lastRequest!.body, isEmpty);
    });

    test('never sends any Business Central customer identifier', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken);

      final query = fake.lastRequest!.url.queryParameters;
      for (final key in [
        'Sell_to_Customer_No',
        'Customer_No',
        'customerNo',
        'customer_id',
        'bc_customer_no',
      ]) {
        expect(query.containsKey(key), isFalse);
      }
      expect(fake.lastRequest!.body, isEmpty);
    });

    test('never constructs a request from next_page_url/path (no such method '
        'parameter exists)', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken, page: 2);

      expect(fake.lastRequest!.url.path, '/api/business-central/invoices');
      expect(fake.lastRequest!.url.queryParameters['page'], '2');
    });

    test('clamps page below 1 up to 1', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken, page: 0);

      expect(fake.lastRequest!.url.queryParameters['page'], '1');
    });

    test('clamps per_page to the configured maximum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken, perPage: 9999);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '100');
    });

    test('clamps per_page below the configured minimum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken, perPage: 0);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '1');
    });

    test(
      'parses a 200 body into PaginatedResponse<BusinessCentralInvoiceLine>',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        final response = await client.fetchInvoices(token: syntheticToken);

        expect(response, isA<PaginatedResponse<BusinessCentralInvoiceLine>>());
        expect(response.data, hasLength(1));
        expect(response.data.single.documentNo, 'INV-1001');
        expect(response.data.single.lineNo, 10000);
      },
    );

    test('parses an empty page (no rows)', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: const []), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInvoices(token: syntheticToken);

      expect(response.data, isEmpty);
      expect(response.total, 0);
    });

    test(
      'parses a row containing only the documented approved fields',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(
            200,
            validEnvelope(data: [_validInvoiceLineJson()]),
            request: req,
          ),
        );
        final client = AncApiClient(httpClient: fake);

        final response = await client.fetchInvoices(token: syntheticToken);

        expect(response.data.single.documentNo, 'INV-1001');
        expect(response.data.single.orderNo, 'ORD-8829');
      },
    );

    test('parses a row containing every observed extra/undocumented live field '
        'without failing, and never exposes Unit_Cost_LCY', () async {
      final rowWithExtras = {
        ..._validInvoiceLineJson(),
        '@odata.etag': 'W/"JzQ0O1234567890abcdef;1234567\'"',
        'Variant_Code': '',
        'Description_2': '',
        'Shortcut_Dimension_1_Code': '',
        'Shortcut_Dimension_2_Code': '',
        'Unit_of_Measure_Code': 'ROLL',
        'Unit_of_Measure': 'Rolls',
        'Unit_Cost_LCY': 612.5,
        'Line_Discount_Percent': 0,
        'Line_Discount_Amount': 0,
        'Allow_Invoice_Disc': true,
        'Inv_Discount_Amount': 0,
        'Appl_to_Item_Entry': 0,
        'Job_No': '',
      };
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [rowWithExtras]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInvoices(token: syntheticToken);

      expect(response.data, hasLength(1));
      expect(response.data.single.documentNo, 'INV-1001');
      expect(response.data.single.toString(), isNot(contains('612.5')));
    });

    test('a missing Posting_Date on a row still parses successfully', () async {
      final rowWithoutPostingDate = _validInvoiceLineJson()
        ..remove('Posting_Date');
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [rowWithoutPostingDate]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInvoices(token: syntheticToken);

      expect(response.data.single.postingDate, isNull);
    });

    test('a valid Posting_Date on a row parses correctly', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [_validInvoiceLineJson()]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInvoices(token: syntheticToken);

      expect(response.data.single.postingDate, DateTime(2026, 1, 5));
    });

    test('a malformed invoice-line row (missing Document_No) raises '
        'AncProtocolException', () async {
      final badRow = _validInvoiceLineJson()..remove('Document_No');
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: [badRow]), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchInvoices(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test('an invoice-line row using Payments-style camelCase keys raises '
        'AncProtocolException rather than silently parsing', () async {
      final camelCaseRow = {
        'documentNo': 'INV-1001',
        'lineNo': 10000,
        'postingDate': '2026-01-05',
        'sellToCustomerNo': 'CLNT-0001',
        'sellToCustomerName': 'Test Customer One',
        'type': 'Item',
        'itemNo': 'ITEM-001',
        'description': 'Egyptian Cotton Sateen (600TC)',
        'quantity': 12,
        'unitPrice': 850.0,
        'amount': 10200.0,
        'amountIncludingVat': 10710.0,
        'orderNo': 'ORD-8829',
      };
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [camelCaseRow]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchInvoices(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test(
      'a malformed envelope (missing data) raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope.remove('data');
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchInvoices(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a 200 body with non-array data raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope['data'] = {'not': 'an array'};
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchInvoices(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchInvoices(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test(
      'a pagination 422 exposes errors.page through validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'page': ['The page field must be at least 1.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchInvoices(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError?.errors.containsKey('page'), isTrue);
        }
      },
    );

    test(
      'an account-not-linked 422 exposes its message via validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'No linked Business Central customer.',
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchInvoices(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(
            error.validationError?.message,
            'No linked Business Central customer.',
          );
        }
      },
    );

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchInvoices(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchInvoices(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('a network failure raises AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchInvoices(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test(
      'a malformed (non-JSON) 200 body raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchInvoices(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('only ever uses the synthetic test token, never a real one', () {
      expect(syntheticToken, startsWith('synthetic-'));
    });

    test('order_no is omitted from the query when not supplied', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInvoices(token: syntheticToken);

      expect(
        fake.lastRequest!.url.queryParameters.containsKey('order_no'),
        isFalse,
      );
    });

    test(
      'order_no is included alongside page and per_page when supplied',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchInvoices(
          token: syntheticToken,
          page: 1,
          perPage: 100,
          orderNo: 'SO-24001',
        );

        expect(fake.lastRequest!.url.queryParameters, {
          'page': '1',
          'per_page': '100',
          'order_no': 'SO-24001',
        });
      },
    );
  });

  group('AncApiClient.fetchSalesOrders', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    Map<String, dynamic> validEnvelope({
      List<Map<String, dynamic>>? data,
      int currentPage = 1,
      int lastPage = 1,
    }) {
      final rows = data ?? [_validSalesOrderLineJson()];
      return {
        'current_page': currentPage,
        'data': rows,
        'first_page_url': '/?page=1',
        'from': rows.isEmpty ? null : 1,
        'last_page': lastPage,
        'last_page_url': '/?page=$lastPage',
        'next_page_url': currentPage < lastPage
            ? '/?page=${currentPage + 1}'
            : null,
        'path': '/',
        'per_page': 25,
        'prev_page_url': null,
        'to': rows.isEmpty ? null : rows.length,
        'total': rows.length,
      };
    }

    test('GETs the exact sales-orders URI with page and per_page', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken);

      expect(fake.lastRequest!.method, 'GET');
      expect(
        fake.lastRequest!.url,
        Uri.parse(
          'https://api.ancfab.com/api/business-central/sales-orders'
          '?page=1&per_page=25',
        ),
      );
    });

    test(
      'never uses the Zebra sales-orders path, only the ANC API path',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchSalesOrders(token: syntheticToken);

        expect(
          fake.lastRequest!.url.path,
          '/api/business-central/sales-orders',
        );
        expect(fake.lastRequest!.url.host, 'api.ancfab.com');
      },
    );

    test('sends Accept: application/json and Authorization: Bearer <token>, '
        'never a request body', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken);

      expect(fake.lastRequest!.headers['Accept'], 'application/json');
      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(fake.lastRequest!.body, isEmpty);
    });

    test('never sends any Business Central customer identifier', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken);

      final query = fake.lastRequest!.url.queryParameters;
      for (final key in [
        'Sell_to_Customer_No',
        'Customer_No',
        'customerNo',
        'customer_id',
        'bc_customer_no',
      ]) {
        expect(query.containsKey(key), isFalse);
      }
      expect(fake.lastRequest!.body, isEmpty);
    });

    test('page defaults to 1', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken);

      expect(fake.lastRequest!.url.queryParameters['page'], '1');
    });

    test('per_page defaults to 25', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '25');
    });

    test('requests page 2 when asked, never constructing the request from '
        'next_page_url', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken, page: 2);

      expect(fake.lastRequest!.url.path, '/api/business-central/sales-orders');
      expect(fake.lastRequest!.url.queryParameters['page'], '2');
    });

    test('clamps page below 1 up to 1, never requesting page 0', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken, page: 0);

      expect(fake.lastRequest!.url.queryParameters['page'], '1');
    });

    test('per_page never exceeds the configured maximum of 100', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken, perPage: 9999);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '100');
    });

    test('clamps per_page below the configured minimum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken, perPage: 0);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '1');
    });

    test(
      'parses a 200 body into PaginatedResponse<BusinessCentralSalesOrderLine>',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        final response = await client.fetchSalesOrders(token: syntheticToken);

        expect(
          response,
          isA<PaginatedResponse<BusinessCentralSalesOrderLine>>(),
        );
        expect(response.data, hasLength(1));
        expect(response.data.single.documentNo, 'SO-24001');
        expect(response.data.single.lineNo, 10000);
        expect(response.data.single.itemNo, '880107');
      },
    );

    test('preserves the Laravel pagination envelope fields', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(currentPage: 2, lastPage: 10),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchSalesOrders(
        token: syntheticToken,
        page: 2,
      );

      expect(response.currentPage, 2);
      expect(response.lastPage, 10);
      expect(response.from, 1);
      expect(response.to, 1);
      expect(response.total, 1);
    });

    test('parses an empty page (no rows)', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: const []), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchSalesOrders(token: syntheticToken);

      expect(response.data, isEmpty);
      expect(response.total, 0);
      expect(response.from, isNull);
      expect(response.to, isNull);
    });

    test('two rows sharing one Document_No but different Line_No both '
        'parse as separate rows, never grouped', () async {
      final rows = [
        _validSalesOrderLineJson(),
        {..._validSalesOrderLineJson(), 'Line_No': 20000},
      ];
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: rows), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchSalesOrders(token: syntheticToken);

      expect(response.data, hasLength(2));
      expect(response.data[0].documentNo, 'SO-24001');
      expect(response.data[0].lineNo, 10000);
      expect(response.data[1].documentNo, 'SO-24001');
      expect(response.data[1].lineNo, 20000);
      expect(response.data[0].identity, isNot(response.data[1].identity));
    });

    test('a malformed sales-order-line row (missing Document_No) raises '
        'AncProtocolException', () async {
      final badRow = _validSalesOrderLineJson()..remove('Document_No');
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: [badRow]), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchSalesOrders(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test('a malformed sales-order-line row (missing Line_No) raises '
        'AncProtocolException', () async {
      final badRow = _validSalesOrderLineJson()..remove('Line_No');
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: [badRow]), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchSalesOrders(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test(
      'a malformed envelope (missing data) raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope.remove('data');
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchSalesOrders(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchSalesOrders(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test(
      'a pagination 422 exposes errors.page through validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'page': ['The page field must be at least 1.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchSalesOrders(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError?.errors.containsKey('page'), isTrue);
        }
      },
    );

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchSalesOrders(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchSalesOrders(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('a network failure raises AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchSalesOrders(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test(
      'a malformed (non-JSON) 200 body raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchSalesOrders(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('only ever uses the synthetic test token, never a real one', () {
      expect(syntheticToken, startsWith('synthetic-'));
    });

    test('document_no is omitted from the query when not supplied', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchSalesOrders(token: syntheticToken);

      expect(
        fake.lastRequest!.url.queryParameters.containsKey('document_no'),
        isFalse,
      );
    });

    test(
      'document_no is included alongside page and per_page when supplied',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchSalesOrders(
          token: syntheticToken,
          page: 1,
          perPage: 100,
          documentNo: 'SO-24001',
        );

        expect(fake.lastRequest!.url.queryParameters, {
          'page': '1',
          'per_page': '100',
          'document_no': 'SO-24001',
        });
      },
    );
  });

  group('AncApiClient.fetchItems', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    Map<String, dynamic> validEnvelope({
      List<Map<String, dynamic>>? data,
      int currentPage = 1,
      int lastPage = 46,
    }) {
      final rows = data ?? [_validItemJson()];
      return {
        'current_page': currentPage,
        'data': rows,
        'first_page_url': '/?page=1',
        'from': rows.isEmpty ? null : 1,
        'last_page': lastPage,
        'last_page_url': '/?page=$lastPage',
        // Confirmed live defect: next_page_url drops the endpoint path.
        'next_page_url': currentPage < lastPage
            ? '/?page=${currentPage + 1}'
            : null,
        'path': '/',
        'per_page': 25,
        'prev_page_url': null,
        'to': rows.isEmpty ? null : rows.length,
        'total': 1130,
        // Extra, undocumented top-level key the live envelope also
        // returns — must be safely ignored, never cause a parse failure.
        'links': [
          {'url': null, 'label': '&laquo; Previous', 'active': false},
          {'url': '/?page=1', 'label': '1', 'active': true},
        ],
      };
    }

    test('GETs the exact items URI with page and per_page', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchItems(token: syntheticToken);

      expect(fake.lastRequest!.method, 'GET');
      expect(
        fake.lastRequest!.url,
        Uri.parse(
          'https://api.ancfab.com/api/business-central/items'
          '?page=1&per_page=25',
        ),
      );
    });

    test('sends Accept: application/json and Authorization: Bearer <token>, '
        'never a request body', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchItems(token: syntheticToken);

      expect(fake.lastRequest!.headers['Accept'], 'application/json');
      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(fake.lastRequest!.body, isEmpty);
    });

    test('clamps page below 1 up to 1', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchItems(token: syntheticToken, page: 0);

      expect(fake.lastRequest!.url.queryParameters['page'], '1');
    });

    test(
      'clamps per_page to the configured maximum (never sends above 100)',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchItems(token: syntheticToken, perPage: 9999);

        expect(fake.lastRequest!.url.queryParameters['per_page'], '100');
      },
    );

    test('clamps per_page below the configured minimum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchItems(token: syntheticToken, perPage: 0);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '1');
    });

    test(
      'parses a 200 body into PaginatedResponse<BusinessCentralItem>',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        final response = await client.fetchItems(token: syntheticToken);

        expect(response, isA<PaginatedResponse<BusinessCentralItem>>());
        expect(response.data, hasLength(1));
        expect(response.data.single.itemNo, 'ITEM-001');
        expect(response.data.single.id, 'd472efc4-9f2b-4a1a-9e7a-1234567890ab');
        // The confirmed live envelope's extra top-level 'links' key must
        // never cause a parse failure.
        expect(response.currentPage, 1);
        expect(response.lastPage, 46);
      },
    );

    test('parses an integer inventory value correctly', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [_validItemJson(inventory: 993)]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchItems(token: syntheticToken);

      expect(response.data.single.inventory, 993.0);
    });

    test('parses a decimal inventory value correctly', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [_validItemJson(inventory: 703.8)]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchItems(token: syntheticToken);

      expect(response.data.single.inventory, 703.8);
    });

    test('parses an empty page (no rows)', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: const []), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchItems(token: syntheticToken);

      expect(response.data, isEmpty);
    });

    test(
      'a malformed envelope (missing data) raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope.remove('data');
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchItems(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a malformed item row (missing itemNo) raises AncProtocolException',
      () async {
        final badRow = _validItemJson()..remove('itemNo');
        final fake = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, validEnvelope(data: [badRow]), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchItems(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchItems(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test(
      'a pagination 422 exposes errors.page through validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'page': ['The page field must be at least 1.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchItems(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError?.errors.containsKey('page'), isTrue);
        }
      },
    );

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchItems(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchItems(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('a network failure raises AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchItems(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test(
      'a malformed (non-JSON) 200 body raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchItems(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a 200 body with non-array data raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope['data'] = {'not': 'an array'};
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchItems(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('only ever uses the synthetic test token, never a real one', () {
      expect(syntheticToken, startsWith('synthetic-'));
    });
  });

  group('AncApiClient.fetchInventory', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    Map<String, dynamic> validEnvelope({
      List<Map<String, dynamic>>? data,
      int currentPage = 1,
      int lastPage = 1,
    }) {
      final rows = data ?? [_validInventoryEntryJson()];
      return {
        'current_page': currentPage,
        'data': rows,
        'first_page_url': '/?page=1',
        'from': rows.isEmpty ? null : 1,
        'last_page': lastPage,
        'last_page_url': '/?page=$lastPage',
        'next_page_url': currentPage < lastPage
            ? '/?page=${currentPage + 1}'
            : null,
        'path': '/',
        'per_page': 25,
        'prev_page_url': null,
        'to': rows.isEmpty ? null : rows.length,
        'total': rows.length,
        // Extra, undocumented top-level key a live envelope might also
        // return — must be safely ignored, never cause a parse failure.
        'links': [
          {'url': null, 'label': '&laquo; Previous', 'active': false},
          {'url': '/?page=1', 'label': '1', 'active': true},
        ],
      };
    }

    test('GETs the exact inventory URI with page and per_page', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInventory(token: syntheticToken);

      expect(fake.lastRequest!.method, 'GET');
      expect(
        fake.lastRequest!.url,
        Uri.parse(
          'https://api.ancfab.com/api/business-central/inventory'
          '?page=1&per_page=25',
        ),
      );
    });

    test('sends Accept: application/json and Authorization: Bearer <token>, '
        'never a request body', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInventory(token: syntheticToken);

      expect(fake.lastRequest!.headers['Accept'], 'application/json');
      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(fake.lastRequest!.body, isEmpty);
    });

    test('sends page as the exact requested value', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(currentPage: 3, lastPage: 5),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInventory(token: syntheticToken, page: 3);

      expect(fake.lastRequest!.url.queryParameters['page'], '3');
    });

    test('clamps page below 1 up to 1', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInventory(token: syntheticToken, page: 0);

      expect(fake.lastRequest!.url.queryParameters['page'], '1');
    });

    test(
      'clamps per_page to the configured maximum (never sends above 100)',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchInventory(token: syntheticToken, perPage: 9999);

        expect(fake.lastRequest!.url.queryParameters['per_page'], '100');
      },
    );

    test('clamps per_page below the configured minimum', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInventory(token: syntheticToken, perPage: 0);

      expect(fake.lastRequest!.url.queryParameters['per_page'], '1');
    });

    test(
      'parses a 200 body into PaginatedResponse<BusinessCentralInventoryEntry>, '
      'ignoring the extra top-level links key',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        final response = await client.fetchInventory(token: syntheticToken);

        expect(
          response,
          isA<PaginatedResponse<BusinessCentralInventoryEntry>>(),
        );
        expect(response.data, hasLength(1));
        expect(response.data.single.itemNo, 'ITEM-001');
        expect(response.data.single.id, 'd472efc4-9f2b-4a1a-9e7a-1234567890ab');
      },
    );

    test('parses an integer quantity/remainingQuantity correctly', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(
            data: [
              _validInventoryEntryJson(quantity: 100, remainingQuantity: 40),
            ],
          ),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInventory(token: syntheticToken);

      expect(response.data.single.quantity, 100.0);
      expect(response.data.single.remainingQuantity, 40.0);
    });

    test('parses a decimal quantity/remainingQuantity correctly', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(
            data: [
              _validInventoryEntryJson(
                quantity: 100.75,
                remainingQuantity: 39.5,
              ),
            ],
          ),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInventory(token: syntheticToken);

      expect(response.data.single.quantity, 100.75);
      expect(response.data.single.remainingQuantity, 39.5);
    });

    test('ignores unknown/vendor-reference row fields', () async {
      final rowWithExtras = {
        ..._validInventoryEntryJson(),
        '@odata.etag': 'W/"JzQ0O1234567890abcdef;1234567\'"',
        'Vendor_No': 'VEND-001',
        'Unit_Cost_LCY': 612.5,
      };
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(
          200,
          validEnvelope(data: [rowWithExtras]),
          request: req,
        ),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInventory(token: syntheticToken);

      expect(response.data, hasLength(1));
      expect(response.data.single.itemNo, 'ITEM-001');
    });

    test('parses an empty page (no rows)', () async {
      final fake = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, validEnvelope(data: const []), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final response = await client.fetchInventory(token: syntheticToken);

      expect(response.data, isEmpty);
    });

    test(
      'a malformed envelope (missing data) raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope.remove('data');
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchInventory(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a malformed inventory row (missing itemNo) raises AncProtocolException',
      () async {
        final badRow = _validInventoryEntryJson()..remove('itemNo');
        final fake = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, validEnvelope(data: [badRow]), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchInventory(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchInventory(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test(
      'a pagination 422 exposes errors.page through validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'page': ['The page field must be at least 1.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchInventory(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError?.errors.containsKey('page'), isTrue);
        }
      },
    );

    test(
      'a per_page-only 422 also exposes it through validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'per_page': ['The per page field must not be greater than 100.'],
            },
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchInventory(token: syntheticToken, perPage: 9999);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(error.validationError?.errors.containsKey('per_page'), isTrue);
        }
      },
    );

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchInventory(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchInventory(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('a network failure raises AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchInventory(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test(
      'a malformed (non-JSON) 200 body raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchInventory(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'a 200 body with non-array data raises AncProtocolException',
      () async {
        final envelope = validEnvelope();
        envelope['data'] = {'not': 'an array'};
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, envelope, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchInventory(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('only ever uses the synthetic test token, never a real one', () {
      expect(syntheticToken, startsWith('synthetic-'));
    });

    test('item_no is omitted from the query when not supplied', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInventory(token: syntheticToken);

      expect(
        fake.lastRequest!.url.queryParameters.containsKey('item_no'),
        isFalse,
      );
      expect(
        fake.lastRequest!.url.queryParameters.keys,
        containsAll(['page', 'per_page']),
      );
    });

    test(
      'item_no is included alongside page and per_page when supplied',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchInventory(
          token: syntheticToken,
          page: 1,
          perPage: 100,
          itemNo: 'ITEM-001',
        );

        expect(fake.lastRequest!.url.queryParameters, {
          'page': '1',
          'per_page': '100',
          'item_no': 'ITEM-001',
        });
      },
    );

    test('an internal space in item_no is percent-encoded as %20, and the '
        'logical value reaching the backend is unchanged', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, validEnvelope(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchInventory(token: syntheticToken, itemNo: '1038 01');

      expect(fake.lastRequest!.url.toString(), contains('item_no=1038%2001'));
      // Uri.queryParameters decodes percent-encoding back to the exact
      // logical value the backend's request parser will see.
      expect(fake.lastRequest!.url.queryParameters['item_no'], '1038 01');
    });

    test(
      'a hyphen/slash in item_no is preserved through the request',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, validEnvelope(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchInventory(
          token: syntheticToken,
          itemNo: 'ITEM-42-A/B',
        );

        expect(fake.lastRequest!.url.queryParameters['item_no'], 'ITEM-42-A/B');
      },
    );
  });

  group('AncApiClient.getAuthenticatedJson query-string encoding', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    Future<Uri> requestedUrl(Map<String, String> queryParameters) async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, const {'data': []}, request: req),
      );
      final client = AncApiClient(httpClient: fake);
      await client.getAuthenticatedJson(
        'api/business-central/inventory',
        token: syntheticToken,
        queryParameters: queryParameters,
      );
      return fake.lastRequest!.url;
    }

    test('a space is percent-encoded as %20, never as +', () async {
      final url = await requestedUrl({'item_no': '1038 01'});

      expect(url.toString(), contains('item_no=1038%2001'));
      expect(url.toString(), isNot(contains('1038+01')));
      expect(url.queryParameters['item_no'], '1038 01');
    });

    test('a hyphen is preserved unescaped', () async {
      final url = await requestedUrl({'item_no': 'ITEM-42'});

      expect(url.toString(), contains('item_no=ITEM-42'));
      expect(url.queryParameters['item_no'], 'ITEM-42');
    });

    test('a slash is percent-encoded and round-trips exactly', () async {
      final url = await requestedUrl({'item_no': 'ITEM/42'});

      expect(url.toString(), contains('item_no=ITEM%2F42'));
      expect(url.queryParameters['item_no'], 'ITEM/42');
    });

    test(
      'a plus sign is percent-encoded, never interpreted as a space',
      () async {
        final url = await requestedUrl({'item_no': '1+1'});

        expect(url.toString(), contains('item_no=1%2B1'));
        expect(url.queryParameters['item_no'], '1+1');
      },
    );

    test(
      'a percent sign is percent-encoded and never double-encoded',
      () async {
        final url = await requestedUrl({'item_no': '50%OFF'});

        expect(url.toString(), contains('item_no=50%25OFF'));
        // Double-encoding would produce %2550OFF (a re-escaped %25); this
        // confirms the literal single-escaped form reaches the wire.
        expect(url.toString(), isNot(contains('%2550OFF')));
        expect(url.queryParameters['item_no'], '50%OFF');
      },
    );

    test(
      'an ampersand inside a value cannot inject an extra query parameter',
      () async {
        final url = await requestedUrl({'item_no': 'A&page=99', 'page': '1'});

        expect(url.toString(), contains('item_no=A%26page%3D99'));
        expect(url.queryParameters['item_no'], 'A&page=99');
        // Proves the embedded "&page=99" was never parsed as a second,
        // overriding "page" parameter.
        expect(url.queryParameters['page'], '1');
      },
    );

    test(
      'an equals sign inside a value cannot corrupt the query structure',
      () async {
        final url = await requestedUrl({'item_no': 'A=B'});

        expect(url.toString(), contains('item_no=A%3DB'));
        expect(url.queryParameters['item_no'], 'A=B');
      },
    );

    test(
      'a Unicode value is percent-encoded as UTF-8 and round-trips exactly',
      () async {
        final url = await requestedUrl({'item_no': 'قماش'});

        expect(url.queryParameters['item_no'], 'قماش');
      },
    );

    test('digit-only pagination values are unaffected — byte-identical to '
        'plain concatenation', () async {
      final url = await requestedUrl({'page': '3', 'per_page': '100'});

      expect(url.toString(), endsWith('?page=3&per_page=100'));
    });
  });

  group('AncApiClient.logout', () {
    const syntheticToken = 'synthetic-id|synthetic-secret';

    _RecordingHttpClient loggedOutHttpClient() => _RecordingHttpClient(
      (req) async =>
          _jsonResponse(200, {'message': 'Logged out.'}, request: req),
    );

    test('POSTs to the exact logout URI', () async {
      final fake = loggedOutHttpClient();
      final client = AncApiClient(httpClient: fake);

      await client.logout(token: syntheticToken);

      expect(fake.lastRequest!.method, 'POST');
      expect(
        fake.lastRequest!.url,
        Uri.parse('https://api.ancfab.com/api/auth/logout'),
      );
    });

    test('sends Authorization: Bearer <token> and Accept headers', () async {
      final fake = loggedOutHttpClient();
      final client = AncApiClient(httpClient: fake);

      await client.logout(token: syntheticToken);

      expect(
        fake.lastRequest!.headers['Authorization'],
        'Bearer $syntheticToken',
      );
      expect(fake.lastRequest!.headers['Accept'], 'application/json');
    });

    test('sends no request body and no Content-Type header', () async {
      final fake = loggedOutHttpClient();
      final client = AncApiClient(httpClient: fake);

      await client.logout(token: syntheticToken);

      expect(fake.lastRequest!.body, isEmpty);
      expect(fake.lastRequest!.headers.containsKey('Content-Type'), isFalse);
    });

    test('never sends any Business Central customer identifier', () async {
      final fake = loggedOutHttpClient();
      final client = AncApiClient(httpClient: fake);

      await client.logout(token: syntheticToken);

      final query = fake.lastRequest!.url.queryParameters;
      for (final key in [
        'Sell_to_Customer_No',
        'Customer_No',
        'customerNo',
        'customer_id',
        'bc_customer_no',
      ]) {
        expect(query.containsKey(key), isFalse);
      }
      expect(query, isEmpty);
    });

    test(
      'always resolves to the fixed ApiConfig.logoutPath on the ANC API host '
      '— no caller-supplied URL parameter exists',
      () async {
        final fake = loggedOutHttpClient();
        final client = AncApiClient(httpClient: fake);

        await client.logout(token: syntheticToken);

        expect(fake.lastRequest!.url.path, '/${ApiConfig.logoutPath}');
        expect(fake.lastRequest!.url.host, ApiConfig.baseUrl.host);
      },
    );

    test('HTTP 200 with the confirmed {"message":"Logged out."} body completes '
        'normally', () async {
      final fake = loggedOutHttpClient();
      final client = AncApiClient(httpClient: fake);

      await expectLater(client.logout(token: syntheticToken), completes);
    });

    test(
      'HTTP 200 with a malformed (non-JSON) body raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.logout(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'HTTP 200 with a non-object JSON body raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _rawResponse(200, '[1, 2, 3]', request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.logout(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'HTTP 200 missing the message field raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, const {}, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.logout(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test(
      'HTTP 200 with a non-String message raises AncProtocolException',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, {'message': 12345}, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.logout(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.logout(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test('HTTP 422 raises AncHttpException with statusCode 422', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(422, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.logout(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 422);
      }
    });

    test('HTTP 500 raises AncHttpException with statusCode 500', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(500, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.logout(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 500);
      }
    });

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.logout(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.logout(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('a timeout raises AncNetworkException', () async {
      final fake = _neverRespondingClient();
      final client = AncApiClient(
        httpClient: fake,
        requestTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        client.logout(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test('a network/client failure raises AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.logout(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test('only ever uses the synthetic test token, never a real one', () {
      expect(syntheticToken, startsWith('synthetic-'));
    });

    test('no thrown exception ever exposes the token in its message', () async {
      final scenarios = <_RecordingHttpClient>[
        _RecordingHttpClient(
          (req) async => _jsonResponse(401, const {}, request: req),
        ),
        _RecordingHttpClient(
          (req) async => _rawResponse(200, 'not json at all', request: req),
        ),
        _RecordingHttpClient(
          (req) async => throw const SocketException('No route to host'),
        ),
      ];

      for (final fake in scenarios) {
        final client = AncApiClient(httpClient: fake);
        try {
          await client.logout(token: syntheticToken);
          fail('Expected an exception');
        } catch (error) {
          expect(error.toString(), isNot(contains(syntheticToken)));
        }
      }
    });
  });
}

Map<String, dynamic> _validLedgerEntryJson() => {
  'Entry_No': 1001,
  'Posting_Date': '2026-01-05',
  'Document_Type': 'Invoice',
  'Document_No': 'INV-TEST-001',
  'Customer_No': 'CLNT-0001',
  'Customer_Name': 'Test Customer One',
  'Currency_Code': 'USD',
  'Amount': 100.50,
  'Remaining_Amount': 100.50,
  'Due_Date': '2026-01-15',
  'Open': true,
};

Map<String, dynamic> _validInvoiceLineJson() => {
  'Document_No': 'INV-1001',
  'Line_No': 10000,
  'Posting_Date': '2026-01-05',
  'Sell_to_Customer_No': 'CLNT-0001',
  'Sell_to_Customer_Name': 'Test Customer One',
  'Type': 'Item',
  'No': 'ITEM-001',
  'Description': 'Egyptian Cotton Sateen (600TC)',
  'Quantity': 12,
  'Unit_Price': 850.0,
  'Amount': 10200.0,
  'Amount_Including_VAT': 10710.0,
  'Order_No': 'ORD-8829',
};

Map<String, dynamic> _validSalesOrderLineJson() => {
  'Document_No': 'SO-24001',
  'Line_No': 10000,
  'Sell_to_Customer_No': 'CLNT-0001',
  'Sell_to_Customer_Name': 'Test Customer One',
  'No.': '880107',
  'Description': 'Test Fabric Item',
  'Quantity': 12,
  'Unit_Price': 15,
  'Amount': 180,
};

Map<String, dynamic> _validPaymentEntryJson() => {
  'entryNo': 1001,
  'postingDate': '2026-01-05',
  'documentNo': 'PAY-001',
  'customerNo': 'CLNT-0001',
  'customerName': 'Test Customer One',
  'currencyCode': 'USD',
  'amount': 100.50,
  'remainingAmount': 0.00,
  'open': false,
  'dueDate': '2026-01-15',
};

Map<String, dynamic> _validInventoryEntryJson({
  Object? quantity = 100,
  Object? remainingQuantity = 40,
}) => {
  'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
  'entryNo': 1001,
  'postingDate': '2026-01-05',
  'documentType': 'Purchase',
  'documentNo': 'PO-1001',
  'itemNo': 'ITEM-001',
  'description': 'Egyptian Cotton Sateen (600TC)',
  'locationCode': 'MAIN',
  'quantity': quantity,
  'remainingQuantity': remainingQuantity,
  'unitOfMeasureCode': 'YRD',
  'open': true,
};

Map<String, dynamic> _validItemJson({
  Object? inventory = 993,
  Object? unitPrice = 12.5,
}) => {
  '@odata.etag': 'W/"JzQ0O1JSRE...ImageValue=="\'',
  'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
  'itemNo': 'ITEM-001',
  'commonItemNo': 'COMMON-001',
  'description': 'Egyptian Cotton Sateen (600TC)',
  'description2': '',
  'baseUnitOfMeasure': 'YRD',
  'itemCategoryCode': 'FABRIC',
  'productGroupCode': 'COTTON',
  'blocked': false,
  'inventory': inventory,
  'unitPrice': unitPrice,
  'gtin': '',
  'Global_Dimension_1_Filter': '',
  'Global_Dimension_2_Filter': '',
  'Location_Filter': '',
  'Drop_Shipment_Filter': '',
  'Variant_Filter': '',
  'Lot_No_Filter': '',
  'Serial_No_Filter': '',
  'Unit_of_Measure_Filter': '',
  'Package_No_Filter': '',
};
