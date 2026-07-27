// Unit tests for PaymentsService: first-page load, load-more append via
// currentPage + 1 (never a next_page_url), fixed perPage preservation,
// duplicate-request guards, stopping when currentPage >= lastPage,
// load-more-failure row preservation, refresh reset, the stale-response
// generation guard, entryNo dedupe, and 401 handoff to the session
// coordinator.
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/payments_service.dart';

import '../helpers/fake_auth_session_store.dart';
import '../helpers/fake_session_expiry_coordinator.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

AuthSession _session() => const AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: 'sample.user',
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

Map<String, dynamic> _entryJson(int entryNo) => {
  'entryNo': entryNo,
  'postingDate': '2026-01-05',
  'documentNo': 'PAY-$entryNo',
  'customerNo': 'CLNT-0001',
  'customerName': 'Test Customer One',
  'currencyCode': 'USD',
  'amount': 100.50,
  'remainingAmount': 0.0,
  'open': false,
  'dueDate': '2026-01-15',
};

/// Uses unsafe/incomplete pagination URLs (mirroring what the real backend
/// has returned for ledger entries: a bare `/?page=2` that drops the
/// endpoint path) to prove PaymentsService never reads or follows them.
Map<String, dynamic> _envelope({
  required List<int> entryNumbers,
  int currentPage = 1,
  int lastPage = 1,
}) => {
  'current_page': currentPage,
  'data': [for (final n in entryNumbers) _entryJson(n)],
  'first_page_url': '/?page=1',
  'from': entryNumbers.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url': '/?page=$lastPage',
  'next_page_url': currentPage < lastPage ? '/?page=${currentPage + 1}' : null,
  'path': '/',
  'per_page': 25,
  'prev_page_url': null,
  'to': entryNumbers.isEmpty ? null : entryNumbers.length,
  'total': entryNumbers.length,
};

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

/// Serves one scripted response per request, in call order, and records
/// every request's URL for assertions.
class _ScriptedHttpClient extends http.BaseClient {
  _ScriptedHttpClient(this._responses);

  final List<Future<http.StreamedResponse> Function(http.Request)> _responses;
  final List<Uri> requestedUrls = [];
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestedUrls.add(req.url);
    requestCount++;
    final handler = _responses.removeAt(0);
    return handler(req);
  }

  @override
  void close() {}
}

void main() {
  group('PaymentsService.loadFirstPage', () {
    test('loads the first page correctly', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001, 1002]),
          request: req,
        ),
      ]);
      final sessionStore = FakeAuthSessionStore()..seed(_session());
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: sessionStore,
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002]);
      expect(fakeHttp.requestCount, 1);
    });

    test(
      'requests the payments endpoint with page=1 and per_page=25',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(entryNumbers: [1001]), request: req),
        ]);
        final service = PaymentsService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();

        expect(
          fakeHttp.requestedUrls.single.path,
          '/api/business-central/payments',
        );
        expect(fakeHttp.requestedUrls.single.queryParameters['page'], '1');
        expect(fakeHttp.requestedUrls.single.queryParameters['per_page'], '25');
      },
    );

    test('never sends a customerNo query parameter', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(entryNumbers: [1001]), request: req),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      final query = fakeHttp.requestedUrls.single.queryParameters;
      expect(query.containsKey('customerNo'), isFalse);
      expect(query.containsKey('Customer_No'), isFalse);
    });

    test(
      'hasNextPage is false when currentPage >= lastPage (stops paging)',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(entryNumbers: [1001]), request: req),
        ]);
        final service = PaymentsService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();

        expect(service.hasNextPage, isFalse);
        await service.loadNextPage();
        expect(fakeHttp.requestCount, 1, reason: 'loadNextPage must no-op');
      },
    );

    test(
      'a duplicate concurrent loadFirstPage call sends only one request',
      () async {
        final completer = Completer<http.StreamedResponse>();
        final fakeHttp = _ScriptedHttpClient([(req) => completer.future]);
        final service = PaymentsService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        final first = service.loadFirstPage();
        final second = service.loadFirstPage();
        await Future<void>.delayed(Duration.zero); // let the HTTP call fire

        expect(fakeHttp.requestCount, 1);
        completer.complete(
          _jsonResponse(
            200,
            _envelope(entryNumbers: [1001]),
            request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
          ),
        );
        await first;
        await second;
      },
    );
  });

  group('PaymentsService.loadNextPage', () {
    test('requests page = currentPage + 1 against the fixed payments endpoint, '
        'never a next_page_url', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1002], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);
      await service.loadNextPage();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002]);
      expect(service.hasNextPage, isFalse);
      expect(fakeHttp.requestCount, 2);

      // Both requests must hit the fixed payments path with page/per_page
      // query params — never the (unsafe, path-dropping) next_page_url
      // the envelope also carries.
      for (final url in fakeHttp.requestedUrls) {
        expect(url.host, 'api.ancfab.com');
        expect(url.path, '/api/business-central/payments');
      }
      expect(fakeHttp.requestedUrls[0].queryParameters['page'], '1');
      expect(fakeHttp.requestedUrls[1].queryParameters['page'], '2');
    });

    test('preserves the original perPage on the load-more request', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1002], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      await service.loadNextPage();

      expect(fakeHttp.requestedUrls[0].queryParameters['per_page'], '25');
      expect(fakeHttp.requestedUrls[1].queryParameters['per_page'], '25');
    });

    test('cannot run twice concurrently', () async {
      final completer = Completer<http.StreamedResponse>();
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) => completer.future,
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();

      final first = service.loadNextPage();
      final second = service.loadNextPage();
      await Future<void>.delayed(Duration.zero); // let the HTTP call fire

      expect(
        fakeHttp.requestCount,
        2,
        reason: 'first page + one load-more only',
      );
      completer.complete(
        _jsonResponse(
          200,
          _envelope(entryNumbers: [1002], currentPage: 2, lastPage: 2),
          request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
        ),
      );
      await first;
      await second;
      expect(service.entries.map((e) => e.entryNo), [1001, 1002]);
    });

    test('a load-more failure preserves existing rows', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();

      await expectLater(
        service.loadNextPage(),
        throwsA(isA<BusinessCentralFailureException>()),
      );

      expect(service.entries.map((e) => e.entryNo), [1001]);
    });

    test('retry after a load-more failure appends only once', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1002], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      await expectLater(
        service.loadNextPage(),
        throwsA(isA<BusinessCentralFailureException>()),
      );

      await service.loadNextPage();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002]);
    });

    test('preserves backend row order across pages', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1003, 1001, 1002], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1005, 1004], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      await service.loadNextPage();

      expect(
        service.entries.map((e) => e.entryNo),
        [1003, 1001, 1002, 1005, 1004],
        reason: 'PaymentsService must not sort rows locally.',
      );
    });

    test('duplicate entryNo rows across pages are not duplicated', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001, 1002], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          // The backend repeats the boundary record 1002.
          _envelope(entryNumbers: [1002, 1003], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      await service.loadNextPage();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002, 1003]);
    });
  });

  group('PaymentsService.refresh', () {
    test('resets pagination and replaces entries', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) async =>
            _jsonResponse(200, _envelope(entryNumbers: [2001]), request: req),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);

      await service.refresh();

      expect(service.entries.map((e) => e.entryNo), [2001]);
      expect(service.hasNextPage, isFalse);
      expect(service.currentPage, 1);
    });

    test('a stale load-more response cannot corrupt refreshed data', () async {
      final loadMoreCompleter = Completer<http.StreamedResponse>();
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) => loadMoreCompleter.future, // load-more: stays pending
        (req) async =>
            _jsonResponse(200, _envelope(entryNumbers: [2001]), request: req),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();

      final loadMoreFuture = service.loadNextPage();
      await service.refresh(); // completes before the stale load-more does

      expect(service.entries.map((e) => e.entryNo), [2001]);

      // The stale load-more now resolves; it must be discarded, not appended.
      loadMoreCompleter.complete(
        _jsonResponse(
          200,
          _envelope(entryNumbers: [1002], currentPage: 2, lastPage: 2),
          request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
        ),
      );
      await loadMoreFuture;

      expect(service.entries.map((e) => e.entryNo), [2001]);
    });
  });

  group('PaymentsService session/failure handling', () {
    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      await expectLater(
        service.loadFirstPage(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(coordinator.handleUnauthorizedCallCount, 1);
    });

    test('a pagination 422 (errors.page) maps to BusinessCentralRequestDefect '
        'and never invokes the session coordinator', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(422, {
          'message': 'The given data was invalid.',
          'errors': {
            'page': ['The page field must be at least 1.'],
          },
        }, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      try {
        await service.loadFirstPage();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralRequestDefect>());
      }
      expect(coordinator.handleUnauthorizedCallCount, 0);
    });

    test('a non-pagination 422 maps to BusinessCentralAccountNotLinked and '
        'preserves the session', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(422, {
          'message': 'No linked Business Central customer.',
        }, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      try {
        await service.loadFirstPage();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralAccountNotLinked>());
      }
      expect(coordinator.handleUnauthorizedCallCount, 0);
    });

    test('HTTP 502 maps to BusinessCentralUpstreamFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      try {
        await service.loadFirstPage();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralUpstreamFailure>());
      }
    });

    test('HTTP 503 maps to BusinessCentralTemporarilyUnavailable', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(503, const {}, request: req),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      try {
        await service.loadFirstPage();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralTemporarilyUnavailable>());
      }
    });

    test('a network failure maps to BusinessCentralNetworkFailure, never '
        'treated as invalid credentials', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => throw const SocketException('No route to host'),
      ]);
      final service = PaymentsService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      try {
        await service.loadFirstPage();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralNetworkFailure>());
      }
    });

    test(
      'a malformed 200 body maps to BusinessCentralProtocolFailure',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => http.StreamedResponse(
            Stream.value(utf8.encode('not json')),
            200,
            request: req,
          ),
        ]);
        final service = PaymentsService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        try {
          await service.loadFirstPage();
          fail('Expected a BusinessCentralFailureException');
        } on BusinessCentralFailureException catch (error) {
          expect(error.outcome, isA<BusinessCentralProtocolFailure>());
        }
      },
    );

    test(
      '422/502/503/network failures do not invoke the session coordinator',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(422, {
            'message': 'No linked Business Central customer.',
          }, request: req),
        ]);
        final coordinator = FakeSessionExpiryCoordinator();
        final service = PaymentsService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: coordinator,
        );

        await expectLater(
          service.loadFirstPage(),
          throwsA(isA<BusinessCentralFailureException>()),
        );
        expect(coordinator.handleUnauthorizedCallCount, 0);
      },
    );
  });
}
