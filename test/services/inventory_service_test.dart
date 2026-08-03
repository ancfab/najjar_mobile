// Unit tests for InventoryService: first-page load, load-more append via
// currentPage + 1 (never a next_page_url — a live response is not yet
// available and every other Business Central list endpoint's confirmed live
// envelope has returned unsafe/incomplete pagination URLs), fixed perPage
// preservation, duplicate-request guards, stopping when currentPage >=
// lastPage or next_page_url is null, load-more-failure row preservation,
// refresh reset, the stale-response generation guard, id-based dedupe (rows
// sharing itemNo or locationCode are both kept — dedup is by id only), 401
// handoff to the session coordinator, and the inventory-specific 422
// mapping (never BusinessCentralAccountNotLinked, since this data is
// company-scoped rather than tied to a linked customer).
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
import 'package:anc_fabrics/services/inventory_service.dart';

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

Map<String, dynamic> _entryJson(
  String id, {
  String itemNo = 'ITEM-001',
  String locationCode = 'MAIN',
}) => {
  'id': id,
  'entryNo': 1001,
  'postingDate': '2026-01-05',
  'documentType': 'Purchase',
  'documentNo': 'PO-1001',
  'itemNo': itemNo,
  'description': 'Egyptian Cotton Sateen (600TC)',
  'locationCode': locationCode,
  'quantity': 100,
  'remainingQuantity': 40,
  'unitOfMeasureCode': 'YRD',
  'open': true,
};

/// Uses unsafe/incomplete pagination URLs (mirroring the shape confirmed
/// live on other Business Central list endpoints: a bare `/?page=2` that
/// drops the endpoint path) to prove InventoryService never reads or
/// follows them.
Map<String, dynamic> _envelope({
  required List<String> ids,
  int currentPage = 1,
  int lastPage = 1,
}) => {
  'current_page': currentPage,
  'data': [for (final id in ids) _entryJson(id)],
  'first_page_url': '/?page=1',
  'from': ids.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url': '/?page=$lastPage',
  'next_page_url': currentPage < lastPage ? '/?page=${currentPage + 1}' : null,
  'path': '/',
  'per_page': 25,
  'prev_page_url': null,
  'to': ids.isEmpty ? null : ids.length,
  'total': ids.length,
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
  group('InventoryService.loadFirstPage', () {
    test('loads the first page correctly', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(ids: ['id-1', 'id-2']), request: req),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.entries.map((e) => e.id), ['id-1', 'id-2']);
      expect(fakeHttp.requestCount, 1);
    });

    test(
      'requests the inventory endpoint with page=1 and per_page=25',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(ids: ['id-1']), request: req),
        ]);
        final service = InventoryService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();

        expect(
          fakeHttp.requestedUrls.single.path,
          '/api/business-central/inventory',
        );
        expect(fakeHttp.requestedUrls.single.queryParameters['page'], '1');
        expect(fakeHttp.requestedUrls.single.queryParameters['per_page'], '25');
      },
    );

    test('parses an empty first page (no rows)', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(ids: const []), request: req),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.entries, isEmpty);
      expect(service.hasNextPage, isFalse);
    });

    test(
      'hasNextPage is false when currentPage >= lastPage (stops paging)',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(ids: ['id-1']), request: req),
        ]);
        final service = InventoryService(
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
      'stops when next_page_url is null even if lastPage bookkeeping agrees',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(ids: ['id-1'], currentPage: 1, lastPage: 1),
            request: req,
          ),
        ]);
        final service = InventoryService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        await service.loadFirstPage();

        expect(service.hasNextPage, isFalse);
      },
    );

    test(
      'a duplicate concurrent loadFirstPage call sends only one request',
      () async {
        final completer = Completer<http.StreamedResponse>();
        final fakeHttp = _ScriptedHttpClient([(req) => completer.future]);
        final service = InventoryService(
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
            _envelope(ids: ['id-1']),
            request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
          ),
        );
        await first;
        await second;
      },
    );
  });

  group('InventoryService.loadNextPage', () {
    test('requests page = currentPage + 1 against the fixed inventory '
        'endpoint, never a next_page_url', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-1'], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-2'], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);
      await service.loadNextPage();

      expect(service.entries.map((e) => e.id), ['id-1', 'id-2']);
      expect(service.hasNextPage, isFalse);
      expect(fakeHttp.requestCount, 2);

      // Both requests must hit the fixed inventory path with page/per_page
      // query params — never the (unsafe, path-dropping) next_page_url
      // the envelope also carries.
      for (final url in fakeHttp.requestedUrls) {
        expect(url.host, 'api.ancfab.com');
        expect(url.path, '/api/business-central/inventory');
      }
      expect(fakeHttp.requestedUrls[0].queryParameters['page'], '1');
      expect(fakeHttp.requestedUrls[1].queryParameters['page'], '2');
    });

    test('preserves the original perPage on the load-more request, never '
        'increasing it', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-1'], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-2'], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = InventoryService(
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
          _envelope(ids: ['id-1'], lastPage: 2),
          request: req,
        ),
        (req) => completer.future,
      ]);
      final service = InventoryService(
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
          _envelope(ids: ['id-2'], currentPage: 2, lastPage: 2),
          request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
        ),
      );
      await first;
      await second;
      expect(service.entries.map((e) => e.id), ['id-1', 'id-2']);
    });

    test('a load-more failure preserves existing rows', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-1'], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();

      await expectLater(
        service.loadNextPage(),
        throwsA(isA<BusinessCentralFailureException>()),
      );

      expect(service.entries.map((e) => e.id), ['id-1']);
    });

    test('retry after a load-more failure appends only once', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-1'], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-2'], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = InventoryService(
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

      expect(service.entries.map((e) => e.id), ['id-1', 'id-2']);
    });

    test('preserves backend row order across pages', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-3', 'id-1', 'id-2'], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-5', 'id-4'], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();
      await service.loadNextPage();

      expect(
        service.entries.map((e) => e.id),
        ['id-3', 'id-1', 'id-2', 'id-5', 'id-4'],
        reason: 'InventoryService must not sort rows locally.',
      );
    });

    test('duplicate id rows across pages are not duplicated', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-1', 'id-2'], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          // The backend repeats the boundary record id-2.
          _envelope(ids: ['id-2', 'id-3'], currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      await service.loadNextPage();

      expect(service.entries.map((e) => e.id), ['id-1', 'id-2', 'id-3']);
    });

    test('entries sharing the same itemNo (different ledger entries) are '
        'both kept — deduplication is by id only', () async {
      final entryA = _entryJson('id-1', itemNo: 'ITEM-001');
      final entryB = _entryJson('id-2', itemNo: 'ITEM-001');
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(200, {
          ..._envelope(ids: const []),
          'data': [entryA, entryB],
        }, request: req),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.entries.map((e) => e.id), ['id-1', 'id-2']);
      expect(service.entries.map((e) => e.itemNo).toSet(), {'ITEM-001'});
    });

    test('entries for the same item at different locations are both kept '
        '— InventoryService never aggregates by itemNo/locationCode', () async {
      final entryMain = _entryJson(
        'id-1',
        itemNo: 'ITEM-001',
        locationCode: 'MAIN',
      );
      final entryAnnex = _entryJson(
        'id-2',
        itemNo: 'ITEM-001',
        locationCode: 'ANNEX',
      );
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(200, {
          ..._envelope(ids: const []),
          'data': [entryMain, entryAnnex],
        }, request: req),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.loadFirstPage();

      expect(service.entries.map((e) => e.id), ['id-1', 'id-2']);
      expect(service.entries.map((e) => e.locationCode).toSet(), {
        'MAIN',
        'ANNEX',
      });
    });
  });

  group('InventoryService.refresh', () {
    test('resets pagination and replaces entries', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-1'], lastPage: 2),
          request: req,
        ),
        (req) async =>
            _jsonResponse(200, _envelope(ids: ['id-99']), request: req),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();
      expect(service.hasNextPage, isTrue);

      await service.refresh();

      expect(service.entries.map((e) => e.id), ['id-99']);
      expect(service.hasNextPage, isFalse);
      expect(service.currentPage, 1);
    });

    test('a stale load-more response cannot corrupt refreshed data', () async {
      final loadMoreCompleter = Completer<http.StreamedResponse>();
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(ids: ['id-1'], lastPage: 2),
          request: req,
        ),
        (req) => loadMoreCompleter.future, // load-more: stays pending
        (req) async =>
            _jsonResponse(200, _envelope(ids: ['id-99']), request: req),
      ]);
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );
      await service.loadFirstPage();

      final loadMoreFuture = service.loadNextPage();
      await service.refresh(); // completes before the stale load-more does

      expect(service.entries.map((e) => e.id), ['id-99']);

      // The stale load-more now resolves; it must be discarded, not appended.
      loadMoreCompleter.complete(
        _jsonResponse(
          200,
          _envelope(ids: ['id-2'], currentPage: 2, lastPage: 2),
          request: http.Request('GET', Uri.parse('https://api.ancfab.com')),
        ),
      );
      await loadMoreFuture;

      expect(service.entries.map((e) => e.id), ['id-99']);
    });
  });

  group('InventoryService session/failure handling', () {
    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = InventoryService(
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
      final service = InventoryService(
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

    test('a 422 with no page/per_page error still maps to '
        'BusinessCentralRequestDefect for inventory, never '
        'BusinessCentralAccountNotLinked — this data is company-scoped, '
        'not tied to a linked customer', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(422, {
          'message': 'The given data was invalid.',
        }, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = InventoryService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      try {
        await service.loadFirstPage();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralRequestDefect>());
        expect(error.outcome, isNot(isA<BusinessCentralAccountNotLinked>()));
      }
      expect(coordinator.handleUnauthorizedCallCount, 0);
    });

    test('HTTP 502 maps to BusinessCentralUpstreamFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = InventoryService(
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
      final service = InventoryService(
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
      final service = InventoryService(
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
        final service = InventoryService(
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
            'message': 'The given data was invalid.',
          }, request: req),
        ]);
        final coordinator = FakeSessionExpiryCoordinator();
        final service = InventoryService(
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
