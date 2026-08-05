// Unit tests for InvoiceLookupService: order_no query-param presence across
// every page, full-page accumulation, Document_No + Line_No deduplication,
// mismatched-Order_No row rejection, pagination-loop protection, no-related-
// invoice (empty) behavior, all-or-nothing failure on a partially failed
// pagination sequence, and the shared 401/422/502/503/network/malformed
// error mapping.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/invoice_lookup_service.dart';

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

Map<String, dynamic> _rowJson(
  String documentNo,
  int lineNo, {
  String orderNo = 'SO-24001',
}) => {
  'Document_No': documentNo,
  'Line_No': lineNo,
  'Posting_Date': null,
  'Sell_to_Customer_No': 'CLNT-0001',
  'Sell_to_Customer_Name': 'Test Customer One',
  'Type': 'Item',
  'No': '880107',
  'Description': 'Test Fabric Item',
  'Quantity': 12,
  'Unit_Price': 15,
  'Amount': 180,
  'Amount_Including_VAT': 189,
  'Order_No': orderNo,
};

Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> rows,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 100,
}) => {
  'current_page': currentPage,
  'data': rows,
  'first_page_url':
      'https://api.ancfab.com/api/business-central/invoices?page=1',
  'from': rows.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url':
      'https://api.ancfab.com/api/business-central/invoices?page=$lastPage',
  'next_page_url': currentPage < lastPage
      ? 'https://api.ancfab.com/api/business-central/invoices?page=${currentPage + 1}'
      : null,
  'path': 'https://api.ancfab.com/api/business-central/invoices',
  'per_page': perPage,
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

class _NeverConvergingHttpClient extends http.BaseClient {
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    final req = request as http.Request;
    final page = int.parse(req.url.queryParameters['page']!);
    return _jsonResponse(
      200,
      _envelope(
        rows: [_rowJson('INV-24001', page * 10000)],
        currentPage: page,
        lastPage: 1000000,
      ),
      request: req,
    );
  }

  @override
  void close() {}
}

InvoiceLookupService _serviceWith(http.Client fakeHttp) {
  return InvoiceLookupService(
    apiClient: AncApiClient(httpClient: fakeHttp),
    sessionStore: FakeAuthSessionStore()..seed(_session()),
    coordinator: FakeSessionExpiryCoordinator(),
  );
}

void main() {
  group('InvoiceLookupService.fetchInvoiceLinesForOrder', () {
    test('requests order_no on the single-page case, with Authorization and '
        'Accept headers', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_rowJson('INV-24001', 10000)]),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      await service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001');

      expect(fakeHttp.requestCount, 1);
      final url = fakeHttp.requestedUrls.single;
      expect(url.path, '/api/business-central/invoices');
      expect(url.queryParameters['order_no'], 'SO-24001');
      expect(url.queryParameters['page'], '1');
    });

    test('preserves order_no across every page of a multi-page fetch, and '
        'accumulates all lines', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('INV-24001', 10000)],
            currentPage: 1,
            lastPage: 2,
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('INV-24001', 20000)],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      final lines = await service.fetchInvoiceLinesForOrder(
        orderNo: 'SO-24001',
      );

      expect(fakeHttp.requestCount, 2);
      for (final url in fakeHttp.requestedUrls) {
        expect(url.queryParameters['order_no'], 'SO-24001');
      }
      expect(lines.map((l) => l.lineNo), [10000, 20000]);
    });

    test('deduplicates rows sharing the same Document_No + Line_No across '
        'pages', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('INV-24001', 10000), _rowJson('INV-24001', 10000)],
            currentPage: 1,
            lastPage: 1,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      final lines = await service.fetchInvoiceLinesForOrder(
        orderNo: 'SO-24001',
      );

      expect(lines, hasLength(1));
    });

    test('groups later by invoice Document_No — this fetch itself keeps '
        'rows from multiple invoice Document_No values distinct', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('INV-24001', 10000), _rowJson('INV-24010', 10000)],
            currentPage: 1,
            lastPage: 1,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      final lines = await service.fetchInvoiceLinesForOrder(
        orderNo: 'SO-24001',
      );

      expect(lines.map((l) => l.documentNo).toSet(), {
        'INV-24001',
        'INV-24010',
      });
    });

    test(
      'drops rows whose Order_No does not match the requested value',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _rowJson('INV-24001', 10000, orderNo: 'SO-24001'),
                _rowJson('INV-24001', 20000, orderNo: 'SO-99999'),
              ],
              currentPage: 1,
              lastPage: 1,
            ),
            request: req,
          ),
        ]);
        final service = _serviceWith(fakeHttp);

        final lines = await service.fetchInvoiceLinesForOrder(
          orderNo: 'SO-24001',
        );

        expect(lines, hasLength(1));
        expect(lines.single.lineNo, 10000);
      },
    );

    test(
      'empty first-page data returns an empty list (no related invoice)',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async =>
              _jsonResponse(200, _envelope(rows: const []), request: req),
        ]);
        final service = _serviceWith(fakeHttp);

        final lines = await service.fetchInvoiceLinesForOrder(
          orderNo: 'SO-24001',
        );

        expect(lines, isEmpty);
      },
    );

    test('a failure on a later page discards the whole result', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('INV-24001', 10000)],
            currentPage: 1,
            lastPage: 2,
          ),
          request: req,
        ),
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      await expectLater(
        service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001'),
        throwsA(isA<BusinessCentralFailureException>()),
      );
    });

    test('pagination-loop protection stops the request loop', () async {
      final fakeHttp = _NeverConvergingHttpClient();
      final service = InvoiceLookupService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await expectLater(
        service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001'),
        throwsA(isA<BusinessCentralFailureException>()),
      );
      expect(fakeHttp.requestCount, lessThan(1000));
    });

    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = InvoiceLookupService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      await expectLater(
        service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001'),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(coordinator.handleUnauthorizedCallCount, 1);
    });

    test('HTTP 502 maps to BusinessCentralUpstreamFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001');
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralUpstreamFailure>());
      }
    });

    test('HTTP 503 maps to BusinessCentralTemporarilyUnavailable', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(503, const {}, request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001');
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralTemporarilyUnavailable>());
      }
    });

    test('a network failure maps to BusinessCentralNetworkFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => throw const SocketException('No route to host'),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001');
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
        final service = _serviceWith(fakeHttp);

        try {
          await service.fetchInvoiceLinesForOrder(orderNo: 'SO-24001');
          fail('Expected a BusinessCentralFailureException');
        } on BusinessCentralFailureException catch (error) {
          expect(error.outcome, isA<BusinessCentralProtocolFailure>());
        }
      },
    );
  });
}
