// Unit tests for SalesOrderLinesService: page/per_page request shape, page
// 1-2-3 navigation, and the shared 401/422/502/503/network/malformed error
// mapping (mirroring LastPaymentService's own test coverage for the same
// taxonomy).
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/sales_order_lines_service.dart';

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

Map<String, dynamic> _rowJson(String documentNo, int lineNo) => {
  'Document_No': documentNo,
  'Line_No': lineNo,
  'Sell_to_Customer_No': 'CLNT-0001',
  'Sell_to_Customer_Name': 'Test Customer One',
  'No.': '880107',
  'Description': 'Test Fabric Item',
  'Quantity': 12,
  'Unit_Price': 15,
  'Amount': 180,
};

Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> rows,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 25,
}) => {
  'current_page': currentPage,
  'data': rows,
  'first_page_url':
      'https://api.ancfab.com/api/business-central/sales-orders?page=1',
  'from': rows.isEmpty ? null : ((currentPage - 1) * perPage) + 1,
  'last_page': lastPage,
  'last_page_url':
      'https://api.ancfab.com/api/business-central/sales-orders?page=$lastPage',
  'next_page_url': currentPage < lastPage
      ? 'https://api.ancfab.com/api/business-central/sales-orders?page=${currentPage + 1}'
      : null,
  'path': 'https://api.ancfab.com/api/business-central/sales-orders',
  'per_page': perPage,
  'prev_page_url': currentPage > 1
      ? 'https://api.ancfab.com/api/business-central/sales-orders?page=${currentPage - 1}'
      : null,
  'to': rows.isEmpty ? null : ((currentPage - 1) * perPage) + rows.length,
  'total': rows.isEmpty ? 0 : 248,
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

SalesOrderLinesService _serviceWith(http.Client fakeHttp) {
  return SalesOrderLinesService(
    apiClient: AncApiClient(httpClient: fakeHttp),
    sessionStore: FakeAuthSessionStore()..seed(_session()),
    coordinator: FakeSessionExpiryCoordinator(),
  );
}

void main() {
  group('SalesOrderLinesService.fetchPage', () {
    test('requests GET /api/business-central/sales-orders with the given '
        'page and per_page, and the Authorization/Accept headers', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_rowJson('SO-24001', 10000)], lastPage: 10),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      await service.fetchPage(page: 1, perPage: 25);

      expect(fakeHttp.requestCount, 1);
      final url = fakeHttp.requestedUrls.single;
      expect(url.path, '/api/business-central/sales-orders');
      expect(url.queryParameters['page'], '1');
      expect(url.queryParameters['per_page'], '25');
    });

    test('preserves per_page across a page 1 -> 2 -> 3 navigation', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('SO-24001', 10000)],
            currentPage: 1,
            lastPage: 10,
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('SO-24002', 10000)],
            currentPage: 2,
            lastPage: 10,
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('SO-24003', 10000)],
            currentPage: 3,
            lastPage: 10,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      await service.fetchPage(page: 1, perPage: 25);
      await service.fetchPage(page: 2, perPage: 25);
      await service.fetchPage(page: 3, perPage: 25);

      expect(fakeHttp.requestCount, 3);
      for (final url in fakeHttp.requestedUrls) {
        expect(url.queryParameters['per_page'], '25');
      }
      expect(fakeHttp.requestedUrls.map((u) => u.queryParameters['page']), [
        '1',
        '2',
        '3',
      ]);
    });

    test('returns the exact rows and pagination metadata the backend '
        'sends back', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_rowJson('SO-24001', 10000)],
            currentPage: 1,
            lastPage: 10,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      final page = await service.fetchPage(page: 1);

      expect(page.data, hasLength(1));
      expect(page.data.single.documentNo, 'SO-24001');
      expect(page.currentPage, 1);
      expect(page.lastPage, 10);
      expect(page.total, 248);
    });

    test('empty data returns an empty page, never mock rows', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: const []), request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      final page = await service.fetchPage(page: 1);

      expect(page.data, isEmpty);
      expect(page.from, isNull);
      expect(page.to, isNull);
    });

    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = SalesOrderLinesService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      await expectLater(
        service.fetchPage(page: 1),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(coordinator.handleUnauthorizedCallCount, 1);
    });

    test('a pagination 422 maps to BusinessCentralRequestDefect', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(422, {
          'message': 'The given data was invalid.',
          'errors': {
            'page': ['The page field must be at least 1.'],
          },
        }, request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchPage(page: 0);
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralRequestDefect>());
      }
    });

    test('HTTP 502 maps to BusinessCentralUpstreamFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchPage(page: 1);
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
        await service.fetchPage(page: 1);
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
        await service.fetchPage(page: 1);
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
          await service.fetchPage(page: 1);
          fail('Expected a BusinessCentralFailureException');
        } on BusinessCentralFailureException catch (error) {
          expect(error.outcome, isA<BusinessCentralProtocolFailure>());
        }
      },
    );

    test(
      '502/503/network failures do not invoke the session coordinator',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(502, const {}, request: req),
        ]);
        final coordinator = FakeSessionExpiryCoordinator();
        final service = SalesOrderLinesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: coordinator,
        );

        await expectLater(
          service.fetchPage(page: 1),
          throwsA(isA<BusinessCentralFailureException>()),
        );
        expect(coordinator.handleUnauthorizedCallCount, 0);
      },
    );
  });
}
