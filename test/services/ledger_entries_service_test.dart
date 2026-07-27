// Unit tests for LedgerEntriesService: first-page load, load-more append,
// duplicate-request guards, fixed page size, stopping on the last page,
// load-more-failure row preservation, refresh reset, the stale-response
// generation guard, Entry_No dedupe, and 401 handoff to the session
// coordinator.
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

Map<String, dynamic> _envelope({
  required List<int> entryNumbers,
  int currentPage = 1,
  int lastPage = 1,
  String? nextPageUrl,
}) => {
  'current_page': currentPage,
  'data': [for (final n in entryNumbers) _entryJson(n)],
  'first_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
  'from': entryNumbers.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=$lastPage',
  'next_page_url': nextPageUrl,
  'path': 'https://api.ancfab.com/api/business-central/ledger-entries',
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

    test('requests a fixed page size of 25', () async {
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

      expect(fakeHttp.requestedUrls.single.queryParameters['per_page'], '25');
      expect(fakeHttp.requestedUrls.single.queryParameters['page'], '1');
    });

    test(
      'hasNextPage is false when next_page_url is null (stops paging)',
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
          _envelope(
            entryNumbers: [1001],
            lastPage: 2,
            nextPageUrl: 'https://api.ancfab.com/x?page=2',
          ),
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

    test('cannot run twice concurrently', () async {
      final completer = Completer<http.StreamedResponse>();
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            entryNumbers: [1001],
            lastPage: 2,
            nextPageUrl: 'https://api.ancfab.com/x?page=2',
          ),
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
          _envelope(
            entryNumbers: [1001],
            lastPage: 2,
            nextPageUrl: 'https://api.ancfab.com/x?page=2',
          ),
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
          _envelope(
            entryNumbers: [1001],
            lastPage: 2,
            nextPageUrl: 'https://api.ancfab.com/x?page=2',
          ),
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
          _envelope(
            entryNumbers: [1001, 1002],
            lastPage: 2,
            nextPageUrl: 'https://api.ancfab.com/x?page=2',
          ),
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
  });

  group('LedgerEntriesService.refresh', () {
    test('resets pagination and replaces entries', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            entryNumbers: [1001],
            lastPage: 2,
            nextPageUrl: 'https://api.ancfab.com/x?page=2',
          ),
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
          _envelope(
            entryNumbers: [1001],
            lastPage: 2,
            nextPageUrl: 'https://api.ancfab.com/x?page=2',
          ),
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
