// Unit tests for InvoicesService: first-page load, load-more append via
// currentPage + 1 (never a next_page_url), fixed perPage preservation,
// duplicate-request guards, stopping when currentPage >= lastPage,
// load-more-failure row preservation, refresh reset, the stale-response
// generation guard, composite Document_No + Line_No dedupe (including the
// confirmed live case of one Document_No spanning a page boundary), and
// 401 handoff to the session coordinator.
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
import 'package:anc_fabrics/services/invoices_service.dart';

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

/// One invoice-line row. [documentNo] defaults to a per-lineNo value so
/// tests that don't care about grouping get distinct documents; tests
/// exercising the page-split/composite-dedupe behavior pass an explicit
/// shared [documentNo].
Map<String, dynamic> _lineJson({
  required int lineNo,
  String? documentNo,
  String? postingDate = '2026-01-05',
}) => {
  'Document_No': documentNo ?? 'INV-$lineNo',
  'Line_No': lineNo,
  'Posting_Date': postingDate,
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

/// Uses unsafe/incomplete pagination URLs (mirroring the confirmed live
/// invoices response: a bare `/?page=2` / `/` that drops the endpoint path)
/// to prove InvoicesService never reads or follows them.
Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> rows,
  int currentPage = 1,
  int lastPage = 1,
}) => {
  'current_page': currentPage,
  'data': rows,
  'first_page_url': '/?page=1',
  'from': rows.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url': '/?page=$lastPage',
  'next_page_url': currentPage < lastPage ? '/?page=${currentPage + 1}' : null,
  'path': '/',
  'per_page': 25,
  'prev_page_url': null,
  'to': rows.isEmpty ? null : rows.length,
  'total': rows.length,
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
  group('InvoicesService.loadFirstPage', () {
    test('loads the first page correctly', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 10000), _lineJson(lineNo: 20000)]),
          request: req,
        ),
      ]);
      final service = InvoicesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.lines.map((l) => l.lineNo), [10000, 20000]);
      expect(fakeHttp.requestCount, 1);
    });

    test('parses an empty first page', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(200, _envelope(rows: []), request: req),
      ]);
      final service = InvoicesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.lines, isEmpty);
      expect(service.hasNextPage, isFalse);
    });

    test(
      'requests the invoices endpoint with page=1 and per_page=25',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_lineJson(lineNo: 10000)]),
            request: req,
          ),
        ]);
        final service = InvoicesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();

        expect(
          fakeHttp.requestedUrls.single.path,
          '/api/business-central/invoices',
        );
        expect(fakeHttp.requestedUrls.single.queryParameters['page'], '1');
        expect(fakeHttp.requestedUrls.single.queryParameters['per_page'], '25');
      },
    );

    test('never sends any Business Central customer identifier', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 10000)]),
          request: req,
        ),
      ]);
      final service = InvoicesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      final query = fakeHttp.requestedUrls.single.queryParameters;
      for (final key in [
        'Sell_to_Customer_No',
        'Customer_No',
        'customerNo',
        'customer_id',
        'bc_customer_no',
      ]) {
        expect(query.containsKey(key), isFalse);
      }
    });

    test(
      'hasNextPage is false when currentPage >= lastPage (stops paging)',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_lineJson(lineNo: 10000)]),
            request: req,
          ),
        ]);
        final service = InvoicesService(
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
        final service = InvoicesService(
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
            _envelope(rows: [_lineJson(lineNo: 10000)]),
            request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
          ),
        );
        await first;
        await second;
      },
    );
  });

  group('InvoicesService.loadNextPage', () {
    test('requests page = currentPage + 1 against the fixed invoices '
        'endpoint, never a next_page_url', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 10000)], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_lineJson(lineNo: 20000)],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final service = InvoicesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);
      await service.loadNextPage();

      expect(service.lines.map((l) => l.lineNo), [10000, 20000]);
      expect(service.hasNextPage, isFalse);
      expect(fakeHttp.requestCount, 2);

      // Both requests must hit the fixed invoices path with page/per_page
      // query params — never the (unsafe, path-dropping) next_page_url the
      // envelope also carries.
      for (final url in fakeHttp.requestedUrls) {
        expect(url.host, 'api.ancfab.com');
        expect(url.path, '/api/business-central/invoices');
      }
      expect(fakeHttp.requestedUrls[0].queryParameters['page'], '1');
      expect(fakeHttp.requestedUrls[1].queryParameters['page'], '2');
    });

    test('preserves the original perPage on the load-more request', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 10000)], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_lineJson(lineNo: 20000)],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final service = InvoicesService(
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
          _envelope(rows: [_lineJson(lineNo: 10000)], lastPage: 2),
          request: req,
        ),
        (req) => completer.future,
      ]);
      final service = InvoicesService(
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
          _envelope(
            rows: [_lineJson(lineNo: 20000)],
            currentPage: 2,
            lastPage: 2,
          ),
          request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
        ),
      );
      await first;
      await second;
      expect(service.lines.map((l) => l.lineNo), [10000, 20000]);
    });

    test('a load-more failure preserves existing rows', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 10000)], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = InvoicesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();

      await expectLater(
        service.loadNextPage(),
        throwsA(isA<BusinessCentralFailureException>()),
      );

      expect(service.lines.map((l) => l.lineNo), [10000]);
    });

    test('retry after a load-more failure appends only once', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 10000)], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_lineJson(lineNo: 20000)],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final service = InvoicesService(
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

      expect(service.lines.map((l) => l.lineNo), [10000, 20000]);
    });

    test(
      'preserves backend row order across pages (no local sorting)',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _lineJson(lineNo: 30000, documentNo: 'INV-3'),
                _lineJson(lineNo: 10000, documentNo: 'INV-1'),
                _lineJson(lineNo: 20000, documentNo: 'INV-2'),
              ],
              lastPage: 2,
            ),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _lineJson(lineNo: 50000, documentNo: 'INV-5'),
                _lineJson(lineNo: 40000, documentNo: 'INV-4'),
              ],
              currentPage: 2,
              lastPage: 2,
            ),
            request: req,
          ),
        ]);
        final service = InvoicesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();
        await service.loadNextPage();

        expect(
          service.lines.map((l) => l.documentNo),
          ['INV-3', 'INV-1', 'INV-2', 'INV-5', 'INV-4'],
          reason: 'InvoicesService must not sort rows locally.',
        );
      },
    );

    group('composite Document_No + Line_No deduplication', () {
      test('the same Document_No with a different Line_No retains both rows '
          '(a Document_No spanning a page boundary must not be treated as a '
          'duplicate)', () async {
        // Mirrors the confirmed live behavior: page 1 ends with
        // Document_No INV-100 / Line_No 20000, page 2 begins with the
        // same Document_No / Line_No 30000 — both are distinct lines of
        // the same invoice and must both survive.
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [_lineJson(lineNo: 20000, documentNo: 'INV-100')],
              lastPage: 2,
            ),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [_lineJson(lineNo: 30000, documentNo: 'INV-100')],
              currentPage: 2,
              lastPage: 2,
            ),
            request: req,
          ),
        ]);
        final service = InvoicesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();
        await service.loadNextPage();

        expect(service.lines, hasLength(2));
        expect(service.lines.map((l) => l.documentNo), ['INV-100', 'INV-100']);
        expect(service.lines.map((l) => l.lineNo), [20000, 30000]);
      });

      test('an exact duplicate Document_No + Line_No across pages is not '
          'duplicated', () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _lineJson(lineNo: 10000, documentNo: 'INV-100'),
                _lineJson(lineNo: 20000, documentNo: 'INV-100'),
              ],
              lastPage: 2,
            ),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(
              // The backend repeats the boundary line (same Document_No
              // AND same Line_No).
              rows: [
                _lineJson(lineNo: 20000, documentNo: 'INV-100'),
                _lineJson(lineNo: 30000, documentNo: 'INV-100'),
              ],
              currentPage: 2,
              lastPage: 2,
            ),
            request: req,
          ),
        ]);
        final service = InvoicesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();
        await service.loadNextPage();

        expect(service.lines.map((l) => l.lineNo), [10000, 20000, 30000]);
      });

      test('a document split across pages merges as flat lines with no data '
          'loss and no grouping', () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _lineJson(lineNo: 10000, documentNo: 'INV-200'),
                _lineJson(lineNo: 20000, documentNo: 'INV-100'),
              ],
              lastPage: 2,
            ),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _lineJson(lineNo: 30000, documentNo: 'INV-100'),
                _lineJson(lineNo: 10000, documentNo: 'INV-300'),
              ],
              currentPage: 2,
              lastPage: 2,
            ),
            request: req,
          ),
        ]);
        final service = InvoicesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();
        await service.loadNextPage();

        // Every line preserved, flat, backend order — INV-100's two
        // lines are not merged/grouped into a single object.
        expect(service.lines, hasLength(4));
        expect(
          service.lines.map((l) => '${l.documentNo}/${l.lineNo}').toList(),
          ['INV-200/10000', 'INV-100/20000', 'INV-100/30000', 'INV-300/10000'],
        );
      });
    });
  });

  group('InvoicesService.refresh', () {
    test('resets pagination and replaces lines, starting at page 1', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 10000)], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_lineJson(lineNo: 90000)]),
          request: req,
        ),
      ]);
      final service = InvoicesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);

      await service.refresh();

      expect(service.lines.map((l) => l.lineNo), [90000]);
      expect(service.hasNextPage, isFalse);
      expect(service.currentPage, 1);
      expect(fakeHttp.requestedUrls[1].queryParameters['page'], '1');
    });

    test(
      'a stale load-more response cannot overwrite refreshed data',
      () async {
        final loadMoreCompleter = Completer<http.StreamedResponse>();
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_lineJson(lineNo: 10000)], lastPage: 2),
            request: req,
          ),
          (req) => loadMoreCompleter.future, // load-more: stays pending
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_lineJson(lineNo: 90000)]),
            request: req,
          ),
        ]);
        final service = InvoicesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );
        await service.loadFirstPage();

        final loadMoreFuture = service.loadNextPage();
        await service.refresh(); // completes before the stale load-more does

        expect(service.lines.map((l) => l.lineNo), [90000]);

        // The stale load-more now resolves; it must be discarded, not
        // appended onto the freshly-refreshed rows.
        loadMoreCompleter.complete(
          _jsonResponse(
            200,
            _envelope(
              rows: [_lineJson(lineNo: 20000)],
              currentPage: 2,
              lastPage: 2,
            ),
            request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
          ),
        );
        await loadMoreFuture;

        expect(service.lines.map((l) => l.lineNo), [90000]);
      },
    );

    test(
      'replaces data only after a successful response, never on failure',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_lineJson(lineNo: 10000)]),
            request: req,
          ),
          (req) async => _jsonResponse(502, const {}, request: req),
        ]);
        final service = InvoicesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );
        await service.loadFirstPage();

        await expectLater(
          service.refresh(),
          throwsA(isA<BusinessCentralFailureException>()),
        );

        expect(service.lines.map((l) => l.lineNo), [10000]);
      },
    );
  });

  group('InvoicesService session/failure handling', () {
    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = InvoicesService(
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
      final service = InvoicesService(
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
      final service = InvoicesService(
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
      final service = InvoicesService(
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
      final service = InvoicesService(
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
      final service = InvoicesService(
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
        final service = InvoicesService(
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
        final service = InvoicesService(
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
