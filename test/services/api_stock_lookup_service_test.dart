// Unit tests for ApiStockLookupService: the production StockLookupService
// adapter that resolves a scanned/typed exact Business Central `itemNo` to
// per-location open stock availability via the filtered
// `GET /api/business-central/inventory?item_no=...` request.
//
// Covers request construction (item_no/page/per_page, whitespace trimming,
// internal-character preservation), defensive multi-page fetching (following
// validated current_page/last_page metadata, never next_page_url, stopping
// exactly at the last page, rejecting malformed/non-advancing/mismatched
// page metadata, and a hard page cap — all of which fail the lookup rather
// than ever returning a truncated success), open/itemNo filtering,
// per-location/unit aggregation using remainingQuantity (never quantity),
// not-found cases, description selection, and the full failure-mapping
// taxonomy (401/422/502/503/network/malformed).
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/api_stock_lookup_service.dart';
import 'package:anc_fabrics/services/stock_lookup_service.dart';

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

Map<String, dynamic> _row({
  String id = 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
  String itemNo = '1038 01',
  String description = 'Egyptian Cotton Sateen (600TC)',
  String locationCode = 'BEIRUT',
  Object? quantity = 100,
  Object? remainingQuantity = 50,
  String unitOfMeasureCode = 'MT',
  bool open = true,
}) => {
  'id': id,
  'entryNo': 1001,
  'postingDate': '2026-01-05',
  'documentType': 'Purchase',
  'documentNo': 'PO-1001',
  'itemNo': itemNo,
  'description': description,
  'locationCode': locationCode,
  'quantity': quantity,
  'remainingQuantity': remainingQuantity,
  'unitOfMeasureCode': unitOfMeasureCode,
  'open': open,
};

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
  'per_page': 100,
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

/// Serves one scripted response per request, in call order (or a repeating
/// last handler when [repeatLast] is true), and records every request's URL.
class _ScriptedHttpClient extends http.BaseClient {
  _ScriptedHttpClient(this._responses, {this.repeatLast = false});

  final List<Future<http.StreamedResponse> Function(http.Request)> _responses;
  final bool repeatLast;
  final List<Uri> requestedUrls = [];
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestedUrls.add(req.url);
    requestCount++;
    final handler = repeatLast && _responses.length == 1
        ? _responses.first
        : _responses.removeAt(0);
    return handler(req);
  }

  @override
  void close() {}
}

ApiStockLookupService _service({
  required http.Client httpClient,
  AuthSession? session,
  FakeSessionExpiryCoordinator? coordinator,
}) {
  final sessionStore = FakeAuthSessionStore();
  if (session != null) sessionStore.seed(session);
  return ApiStockLookupService(
    apiClient: AncApiClient(httpClient: httpClient),
    sessionStore: sessionStore,
    coordinator: coordinator ?? FakeSessionExpiryCoordinator(),
  );
}

void main() {
  group('Request construction', () {
    test(
      'sends item_no, page=1, and per_page=100 on the first request',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(rows: [_row()]), request: req),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        await service.lookup('1038 01');

        expect(
          fakeHttp.requestedUrls.single.path,
          '/api/business-central/inventory',
        );
        expect(
          fakeHttp.requestedUrls.single.queryParameters['item_no'],
          '1038 01',
        );
        expect(fakeHttp.requestedUrls.single.queryParameters['page'], '1');
        expect(
          fakeHttp.requestedUrls.single.queryParameters['per_page'],
          '100',
        );
      },
    );

    test('trims leading/trailing whitespace before requesting', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: [_row()]), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      await service.lookup('  1038 01  ');

      expect(
        fakeHttp.requestedUrls.single.queryParameters['item_no'],
        '1038 01',
      );
    });

    test('preserves an internal space exactly (never rewritten)', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: [_row()]), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      await service.lookup('1038 01');

      expect(
        fakeHttp.requestedUrls.single.toString(),
        contains('item_no=1038%2001'),
      );
    });

    test('preserves hyphens and slashes exactly', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_row(itemNo: 'ITEM-42-A/B')]),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      await service.lookup('ITEM-42-A/B');

      expect(
        fakeHttp.requestedUrls.single.queryParameters['item_no'],
        'ITEM-42-A/B',
      );
    });

    test('an empty code after trimming never reaches the network', () async {
      final fakeHttp = _ScriptedHttpClient([]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('   ');

      expect(result, isA<StockLookupInvalidCode>());
      expect(fakeHttp.requestCount, 0);
    });

    test('never sends country/client_id/bc_customer_no or any company '
        'identifier', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: [_row()]), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      await service.lookup('1038 01');

      final params = fakeHttp.requestedUrls.single.queryParameters;
      expect(params.keys, {'page', 'per_page', 'item_no'});
    });
  });

  group('Multi-page fetching', () {
    test('a single short page issues exactly one request', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: [_row()]), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      await service.lookup('1038 01');

      expect(fakeHttp.requestCount, 1);
    });

    test(
      'fetches every documented page, preserving item_no, following '
      'current_page/last_page and stopping exactly at the last page',
      () async {
        final page1 = [_row(id: 'row-1', locationCode: 'BEIRUT')];
        final page2 = [_row(id: 'row-2', locationCode: 'TRIPOLI')];
        final page3 = [_row(id: 'row-3', locationCode: 'DUBAI')];
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: page1, currentPage: 1, lastPage: 3),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(rows: page2, currentPage: 2, lastPage: 3),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(rows: page3, currentPage: 3, lastPage: 3),
            request: req,
          ),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01') as StockLookupSuccess;

        // Exactly 3 requests — no extra request past the documented last page.
        expect(fakeHttp.requestCount, 3);
        expect(fakeHttp.requestedUrls[0].queryParameters['page'], '1');
        expect(fakeHttp.requestedUrls[1].queryParameters['page'], '2');
        expect(fakeHttp.requestedUrls[2].queryParameters['page'], '3');
        for (final url in fakeHttp.requestedUrls) {
          expect(url.queryParameters['item_no'], '1038 01');
        }
        expect(
          result.availabilityByLocation.map((a) => a.locationCode),
          containsAll(['BEIRUT', 'TRIPOLI', 'DUBAI']),
        );
      },
    );

    test('never requests unfiltered inventory pages (item_no is always '
        'present)', () async {
      final page1 = [_row(id: 'row-1')];
      final page2 = [_row(id: 'row-2')];
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: page1, currentPage: 1, lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(rows: page2, currentPage: 2, lastPage: 2),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      await service.lookup('1038 01');

      expect(fakeHttp.requestCount, 2);
      for (final url in fakeHttp.requestedUrls) {
        expect(url.queryParameters.containsKey('item_no'), isTrue);
      }
    });

    test('hitting the defensive page cap returns StockLookupUnexpectedFailure, '
        'never a truncated StockLookupSuccess', () async {
      final fullPage = List.generate(100, (i) => _row(id: 'row-$i'));
      // Every page always claims more pages remain (last_page: 999) and
      // genuinely advances current_page each time — a legitimate-looking
      // but absurdly large result set this method must still refuse to
      // fully materialize, rather than looping without bound.
      var nextCurrentPage = 1;
      final fakeHttp = _ScriptedHttpClient([
        (req) async {
          final response = _jsonResponse(
            200,
            _envelope(
              rows: fullPage,
              currentPage: nextCurrentPage,
              lastPage: 999,
            ),
            request: req,
          );
          nextCurrentPage++;
          return response;
        },
      ], repeatLast: true);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupUnexpectedFailure>());
      expect(fakeHttp.requestCount, 50);
    });

    test('current_page not advancing between requests is treated as malformed '
        'and returns StockLookupUnexpectedFailure without looping', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_row(id: 'row-1')], currentPage: 1, lastPage: 5),
          request: req,
        ),
        // Requested page 2, but the backend repeats current_page: 1.
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_row(id: 'row-2')], currentPage: 1, lastPage: 5),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupUnexpectedFailure>());
      expect(fakeHttp.requestCount, 2);
    });

    test('an impossible last_page (less than current_page) returns '
        'StockLookupUnexpectedFailure on the very first page', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_row()], currentPage: 2, lastPage: 1),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupUnexpectedFailure>());
      expect(fakeHttp.requestCount, 1);
    });

    test("a response's current_page not matching the page actually requested "
        'returns StockLookupUnexpectedFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        // page=1 requested, but the backend echoes current_page: 5.
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_row()], currentPage: 5, lastPage: 5),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupUnexpectedFailure>());
    });

    test('a later page going malformed discards earlier pages too — no '
        'partial stock result is ever returned', () async {
      final fakeHttp = _ScriptedHttpClient([
        // A perfectly valid first page, with real rows...
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_row(id: 'row-1', locationCode: 'BEIRUT')],
            currentPage: 1,
            lastPage: 3,
          ),
          request: req,
        ),
        // ...followed by a second page whose metadata cannot be trusted.
        (req) async => _jsonResponse(
          200,
          _envelope(rows: const [], currentPage: 1, lastPage: 3),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupUnexpectedFailure>());
      expect(result, isNot(isA<StockLookupSuccess>()));
    });
  });

  group('Filtering and aggregation', () {
    test('sums remainingQuantity by location+unit, keeping locations and units '
        'separate, and ignores the closed row — matches the documented '
        'example', () async {
      final rows = [
        _row(
          id: 'r1',
          locationCode: 'BEIRUT',
          remainingQuantity: 50,
          unitOfMeasureCode: 'MT',
          open: true,
        ),
        _row(
          id: 'r2',
          locationCode: 'BEIRUT',
          remainingQuantity: 30,
          unitOfMeasureCode: 'MT',
          open: true,
        ),
        _row(
          id: 'r3',
          locationCode: 'TRIPOLI',
          remainingQuantity: 20,
          unitOfMeasureCode: 'MT',
          open: true,
        ),
        _row(
          id: 'r4',
          locationCode: 'BEIRUT',
          remainingQuantity: 0,
          unitOfMeasureCode: 'MT',
          open: false,
        ),
      ];
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(200, _envelope(rows: rows), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01') as StockLookupSuccess;

      expect(result.availabilityByLocation, [
        const StockLocationAvailability(
          locationCode: 'BEIRUT',
          remainingQuantity: 80,
          unitOfMeasureCode: 'MT',
        ),
        const StockLocationAvailability(
          locationCode: 'TRIPOLI',
          remainingQuantity: 20,
          unitOfMeasureCode: 'MT',
        ),
      ]);
    });

    test(
      'the same location with different units of measure is kept separate',
      () async {
        final rows = [
          _row(
            id: 'r1',
            locationCode: 'BEIRUT',
            remainingQuantity: 50,
            unitOfMeasureCode: 'MT',
          ),
          _row(
            id: 'r2',
            locationCode: 'BEIRUT',
            remainingQuantity: 10,
            unitOfMeasureCode: 'PCS',
          ),
        ];
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(rows: rows), request: req),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01') as StockLookupSuccess;

        expect(result.availabilityByLocation, hasLength(2));
        expect(
          result.availabilityByLocation.map((a) => a.unitOfMeasureCode).toSet(),
          {'MT', 'PCS'},
        );
      },
    );

    test(
      'uses remainingQuantity, never quantity, as the availability value',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_row(quantity: 999, remainingQuantity: 12)]),
            request: req,
          ),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01') as StockLookupSuccess;

        expect(result.availabilityByLocation.single.remainingQuantity, 12);
      },
    );

    test('rows for a different itemNo are excluded even if returned', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _row(itemNo: '1038 01'),
              _row(itemNo: 'OTHER-ITEM', id: 'other'),
            ],
          ),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01') as StockLookupSuccess;

      expect(result.availabilityByLocation, hasLength(1));
    });

    test(
      'description is the first non-empty description in row order',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _row(id: 'r1', description: ''),
                _row(id: 'r2', description: 'Egyptian Cotton Sateen (600TC)'),
                _row(id: 'r3', description: 'Should never be picked'),
              ],
            ),
            request: req,
          ),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01') as StockLookupSuccess;

        expect(result.description, 'Egyptian Cotton Sateen (600TC)');
      },
    );

    test('a fully empty description is null, never fabricated', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_row(description: '')]),
          request: req,
        ),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01') as StockLookupSuccess;

      expect(result.description, isNull);
    });

    test('itemNo on the result is the exact requested/trimmed value', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: [_row()]), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('  1038 01  ') as StockLookupSuccess;

      expect(result.itemNo, '1038 01');
      expect(result.rawCode, '  1038 01  ');
    });

    test(
      'batchReference stays null — no documented field represents one',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(rows: [_row()]), request: req),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01') as StockLookupSuccess;

        expect(result.batchReference, isNull);
      },
    );
  });

  group('Not-found cases', () {
    test('an empty filtered dataset returns StockLookupNotFound', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: const []), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupNotFound>());
    });

    test(
      'a dataset where every row is closed returns StockLookupNotFound',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _row(open: false),
                _row(id: 'r2', open: false),
              ],
            ),
            request: req,
          ),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01');

        expect(result, isA<StockLookupNotFound>());
      },
    );

    test(
      'a dataset with only mismatched itemNo rows returns StockLookupNotFound',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_row(itemNo: 'OTHER-ITEM')]),
            request: req,
          ),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01');

        expect(result, isA<StockLookupNotFound>());
      },
    );

    test('never returns success with invented zero stock', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: const []), request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isNot(isA<StockLookupSuccess>()));
    });
  });

  group('Session handling', () {
    test('a missing session hands off to the coordinator and returns '
        'StockLookupSessionExpired without any HTTP call', () async {
      final fakeHttp = _ScriptedHttpClient([]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = _service(
        httpClient: fakeHttp,
        coordinator: coordinator,
      ); // no session seeded

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupSessionExpired>());
      expect(coordinator.handleUnauthorizedCallCount, 1);
      expect(fakeHttp.requestCount, 0);
    });

    // Same assertion shape as InventoryService/ItemsService/PaymentsService/
    // InvoicesService's own "401 hands off to the coordinator exactly once"
    // tests (e.g. inventory_service_test.dart) — proof that a stock-lookup
    // 401 is routed through the exact same single SessionExpiryCoordinator
    // as every other protected endpoint, not a second/competing session
    // system. The coordinator itself (session_expiry_coordinator_test.dart)
    // is what actually clears the secure session and navigates to Login;
    // this test only needs to prove this service delegates to it correctly.
    test('HTTP 401 hands off to the coordinator exactly once and returns '
        'StockLookupSessionExpired', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = _service(
        httpClient: fakeHttp,
        session: _session(),
        coordinator: coordinator,
      );

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupSessionExpired>());
      expect(coordinator.handleUnauthorizedCallCount, 1);
    });
  });

  group('Failure mapping', () {
    test('HTTP 502 maps to StockLookupRetryableFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupRetryableFailure>());
    });

    test('HTTP 503 maps to StockLookupTemporarilyUnavailable', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(503, const {}, request: req),
      ]);
      final service = _service(httpClient: fakeHttp, session: _session());

      final result = await service.lookup('1038 01');

      expect(result, isA<StockLookupTemporarilyUnavailable>());
    });

    test(
      'a network/timeout failure maps to StockLookupRetryableFailure',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => throw const SocketException('No route to host'),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01');

        expect(result, isA<StockLookupRetryableFailure>());
      },
    );

    test(
      'a malformed (non-JSON) response maps to StockLookupUnexpectedFailure',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => http.StreamedResponse(
            Stream.value(utf8.encode('not json at all')),
            200,
            request: req,
          ),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01');

        expect(result, isA<StockLookupUnexpectedFailure>());
      },
    );

    test(
      'a 422 (invalid page/per_page or other backend validation failure) '
      'maps to StockLookupUnexpectedFailure — never StockLookupInvalidCode',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(422, {
            'message': 'The given data was invalid.',
            'errors': {
              'per_page': ['The per page field must not be greater than 100.'],
            },
          }, request: req),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01');

        expect(result, isA<StockLookupUnexpectedFailure>());
        expect(result, isNot(isA<StockLookupInvalidCode>()));
      },
    );

    test(
      'an unexpected 4xx/5xx status maps to StockLookupUnexpectedFailure',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(418, const {}, request: req),
        ]);
        final service = _service(httpClient: fakeHttp, session: _session());

        final result = await service.lookup('1038 01');

        expect(result, isA<StockLookupUnexpectedFailure>());
      },
    );
  });
}
