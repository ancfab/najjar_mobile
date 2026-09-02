// Unit tests for LedgerEntriesService: first-page load, load-more append via
// currentPage + 1 (never a next_page_url — see the "never follows
// next_page_url" test below for the exact production bug this guards
// against), fixed page size, duplicate-request guards, stopping on the last
// page, load-more-failure row preservation, refresh reset, the
// stale-response generation guard, Entry_No dedupe, malformed-pagination
// rejection, and 401 handoff to the session coordinator.
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/ledger_entries_service.dart';

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
  'Entry_No': entryNo,
  'Posting_Date': '2026-01-05',
  'Document_Type': 'Invoice',
  'Document_No': 'INV-TEST-$entryNo',
  'Customer_No': 'CLNT-0001',
  'Customer_Name': 'Test Customer One',
  'Currency_Code': 'USD',
  'Amount': 100.50,
  'Remaining_Amount': 100.50,
  'Due_Date': '2026-01-15',
  'Open': true,
};

/// Defaults `next_page_url` to the unsafe/incomplete shape observed from the
/// real backend — a bare `/?page=N` that drops the endpoint path — whenever
/// a next page exists, to prove LedgerEntriesService never reads or follows
/// it. Individual tests may still override [nextPageUrl] explicitly.
Map<String, dynamic> _envelope({
  required List<int> entryNumbers,
  int currentPage = 1,
  int lastPage = 1,
  Object? nextPageUrl = _unset,
}) => {
  'current_page': currentPage,
  'data': [for (final n in entryNumbers) _entryJson(n)],
  'first_page_url': '/?page=1',
  'from': entryNumbers.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url': '/?page=$lastPage',
  'next_page_url': identical(nextPageUrl, _unset)
      ? (currentPage < lastPage ? '/?page=${currentPage + 1}' : null)
      : nextPageUrl,
  'path': '/',
  'per_page': 25,
  'prev_page_url': null,
  'to': entryNumbers.isEmpty ? null : entryNumbers.length,
  'total': entryNumbers.length,
};

const _unset = Object();

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

/// Always answers with a fresh next page, simulating a backend pagination
/// bug where the reported `last_page` never catches up to `current_page` —
/// used to prove [LedgerEntriesService.loadAllPages]'s `maxPages` cap stops
/// an otherwise-unbounded fetch.
class _InfiniteLoopHttpClient extends http.BaseClient {
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestCount++;
    return _jsonResponse(
      200,
      _envelope(
        entryNumbers: [requestCount],
        currentPage: requestCount,
        lastPage: requestCount + 1,
      ),
      request: req,
    );
  }

  @override
  void close() {}
}

void main() {
  group('LedgerEntriesService.loadFirstPage', () {
    test('loads the first page correctly', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001, 1002]),
          request: req,
        ),
      ]);
      final sessionStore = FakeAuthSessionStore()..seed(_session());
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: sessionStore,
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002]);
      expect(fakeHttp.requestCount, 1);
    });

    test(
      'requests the ledger-entries endpoint with page=1 and per_page=25',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(entryNumbers: [1001]), request: req),
        ]);
        final service = LedgerEntriesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();

        expect(
          fakeHttp.requestedUrls.single.path,
          '/api/business-central/ledger-entries',
        );
        expect(fakeHttp.requestedUrls.single.queryParameters['per_page'], '25');
        expect(fakeHttp.requestedUrls.single.queryParameters['page'], '1');
      },
    );

    test(
      'hasNextPage is false when currentPage >= lastPage (stops paging)',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(entryNumbers: [1001]), request: req),
        ]);
        final service = LedgerEntriesService(
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
        final service = LedgerEntriesService(
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

  group('LedgerEntriesService.loadNextPage', () {
    test('appends the next page to entries', () async {
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
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);
      await service.loadNextPage();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002]);
      expect(service.hasNextPage, isFalse);
    });

    test('requests page = currentPage + 1 against the fixed ledger-entries '
        'endpoint, never a next_page_url — reproduces the production bug '
        'where next_page_url resolves to a bare /?page=2 and must not throw '
        'ArgumentError', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          // Exactly the shape observed from the live backend: a relative
          // URL that would fail AncApiClient's trusted-host guard if
          // followed directly.
          _envelope(entryNumbers: [1001], lastPage: 4, nextPageUrl: '/?page=2'),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            entryNumbers: [1002],
            currentPage: 2,
            lastPage: 4,
            nextPageUrl: '/?page=3',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            entryNumbers: [1003],
            currentPage: 3,
            lastPage: 4,
            nextPageUrl: '/?page=4',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1004], currentPage: 4, lastPage: 4),
          request: req,
        ),
      ]);
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      await service.loadNextPage(); // page 2 — the request that used to throw
      await service.loadNextPage(); // page 3
      await service.loadNextPage(); // page 4

      expect(fakeHttp.requestCount, 4);
      expect(service.entries.map((e) => e.entryNo), [1001, 1002, 1003, 1004]);
      expect(service.hasNextPage, isFalse);

      for (final url in fakeHttp.requestedUrls) {
        expect(url.host, 'api.ancfab.com');
        expect(url.path, '/api/business-central/ledger-entries');
      }
      expect(fakeHttp.requestedUrls[0].queryParameters['page'], '1');
      expect(fakeHttp.requestedUrls[1].queryParameters['page'], '2');
      expect(fakeHttp.requestedUrls[2].queryParameters['page'], '3');
      expect(fakeHttp.requestedUrls[3].queryParameters['page'], '4');
    });

    test('preserves the original per_page on the load-more request', () async {
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
      final service = LedgerEntriesService(
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
      final service = LedgerEntriesService(
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
      final service = LedgerEntriesService(
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
      final service = LedgerEntriesService(
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

    test('duplicate Entry_No rows across pages are not duplicated', () async {
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
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      await service.loadNextPage();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002, 1003]);
    });

    test('a non-advancing current_page on a load-more response maps to '
        'BusinessCentralProtocolFailure and preserves existing rows, '
        'instead of looping forever', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 4),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          // Malformed: still reports current_page 1 despite page=2 having
          // been requested.
          _envelope(entryNumbers: [1002], currentPage: 1, lastPage: 4),
          request: req,
        ),
      ]);
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();

      try {
        await service.loadNextPage();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralProtocolFailure>());
      }

      expect(service.entries.map((e) => e.entryNo), [1001]);
      expect(fakeHttp.requestCount, 2, reason: 'must not retry in a loop');
    });

    test('an invalid last_page (0) on the first page maps to '
        'BusinessCentralProtocolFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], currentPage: 1, lastPage: 0),
          request: req,
        ),
      ]);
      final service = LedgerEntriesService(
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

      expect(service.entries, isEmpty);
    });
  });

  group('LedgerEntriesService.loadAllPages', () {
    test('loads every page and combines all entries', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 3),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1002], currentPage: 2, lastPage: 3),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1003], currentPage: 3, lastPage: 3),
          request: req,
        ),
      ]);
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadAllPages();

      expect(service.entries.map((e) => e.entryNo), [1001, 1002, 1003]);
      expect(fakeHttp.requestCount, 3);
      expect(service.hasNextPage, isFalse);
    });

    test('a single-page result makes only one request', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(entryNumbers: [1001]), request: req),
      ]);
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadAllPages();

      expect(fakeHttp.requestCount, 1);
      expect(service.entries.map((e) => e.entryNo), [1001]);
    });

    test('stops at maxPages as a defensive cap against a pagination loop bug '
        '— never fetches unbounded', () async {
      final fakeHttp = _InfiniteLoopHttpClient();
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadAllPages(maxPages: 3);

      expect(fakeHttp.requestCount, 3);
    });

    test('a failure partway through preserves already-loaded pages and '
        'rethrows', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(entryNumbers: [1001], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await expectLater(
        service.loadAllPages(),
        throwsA(isA<BusinessCentralFailureException>()),
      );
      expect(service.entries.map((e) => e.entryNo), [1001]);
    });
  });

  group('LedgerEntriesService.refresh', () {
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
      final service = LedgerEntriesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);

      await service.refresh();

      expect(service.entries.map((e) => e.entryNo), [2001]);
      expect(service.hasNextPage, isFalse);
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
      final service = LedgerEntriesService(
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

  group('LedgerEntriesService session/failure handling', () {
    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = LedgerEntriesService(
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

    test(
      '422/502/503/network failures do not invoke the session coordinator',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(422, {
            'message': 'No linked Business Central customer.',
          }, request: req),
        ]);
        final coordinator = FakeSessionExpiryCoordinator();
        final service = LedgerEntriesService(
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
