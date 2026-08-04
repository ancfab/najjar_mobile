// Unit tests for LastPaymentService: the confirmed page=1/per_page=1
// request shape, the selectLatestPayment tie-break algorithm, empty-data
// handling, and the shared 401/422/502/503/network/malformed error mapping
// (mirroring PaymentsService's own test coverage for the same taxonomy).
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/business_central/payment_entry.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/last_payment_service.dart';

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
  int entryNo, {
  String postingDate = '2026-01-05',
  double amount = -200.0,
  double remainingAmount = 0.0,
  String currencyCode = 'AED',
}) => {
  'entryNo': entryNo,
  'postingDate': postingDate,
  'documentNo': 'PAY-$entryNo',
  'customerNo': 'CLNT-0001',
  'customerName': 'Test Customer One',
  'currencyCode': currencyCode,
  'amount': amount,
  'remainingAmount': remainingAmount,
  'open': false,
  'dueDate': postingDate,
};

Map<String, dynamic> _envelope(List<Map<String, dynamic>> rows) => {
  'current_page': 1,
  'data': rows,
  'first_page_url': '/?page=1',
  'from': rows.isEmpty ? null : 1,
  'last_page': 1,
  'last_page_url': '/?page=1',
  'next_page_url': null,
  'path': '/',
  'per_page': 1,
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
/// every request's URL/headers for assertions.
class _ScriptedHttpClient extends http.BaseClient {
  _ScriptedHttpClient(this._responses);

  final List<Future<http.StreamedResponse> Function(http.Request)> _responses;
  final List<Uri> requestedUrls = [];
  final List<Map<String, String>> requestedHeaders = [];
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestedUrls.add(req.url);
    requestedHeaders.add(req.headers);
    requestCount++;
    final handler = _responses.removeAt(0);
    return handler(req);
  }

  @override
  void close() {}
}

void main() {
  group('selectLatestPayment', () {
    test('returns null for an empty list', () {
      expect(selectLatestPayment(const []), isNull);
    });

    test('returns the only entry for a single-row list', () {
      final entry = PaymentEntry.fromJson(_entryJson(2001));
      expect(selectLatestPayment([entry]), same(entry));
    });

    test('picks the row with the later postingDate', () {
      final older = PaymentEntry.fromJson(
        _entryJson(1001, postingDate: '2026-01-01'),
      );
      final newer = PaymentEntry.fromJson(
        _entryJson(1002, postingDate: '2026-01-05'),
      );

      expect(selectLatestPayment([older, newer]), same(newer));
      expect(selectLatestPayment([newer, older]), same(newer));
    });

    test('when postingDate ties, picks the row with the higher entryNo', () {
      final lowerEntryNo = PaymentEntry.fromJson(
        _entryJson(1001, postingDate: '2026-01-05'),
      );
      final higherEntryNo = PaymentEntry.fromJson(
        _entryJson(1002, postingDate: '2026-01-05'),
      );

      expect(
        selectLatestPayment([lowerEntryNo, higherEntryNo]),
        same(higherEntryNo),
      );
      expect(
        selectLatestPayment([higherEntryNo, lowerEntryNo]),
        same(higherEntryNo),
      );
    });

    test('never selects by remainingAmount', () {
      final entry = PaymentEntry.fromJson(
        _entryJson(2001, amount: -200.0, remainingAmount: 999.99),
      );
      final selected = selectLatestPayment([entry]);
      expect(selected!.amount, -200.0);
      expect(selected.remainingAmount, 999.99);
    });
  });

  group('LastPaymentService.fetchLatestPayment', () {
    test('requests GET /api/business-central/payments with page=1, per_page=1, '
        'and the Authorization/Accept headers', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope([_entryJson(2001)]), request: req),
      ]);
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.fetchLatestPayment();

      expect(fakeHttp.requestCount, 1);
      final url = fakeHttp.requestedUrls.single;
      expect(url.path, '/api/business-central/payments');
      expect(url.queryParameters['page'], '1');
      expect(url.queryParameters['per_page'], '1');

      final headers = fakeHttp.requestedHeaders.single;
      expect(headers['Authorization'], 'Bearer $_syntheticToken');
      expect(headers['Accept'], 'application/json');
    });

    test('returns the single row the endpoint sends back', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope([_entryJson(2001, currencyCode: 'AED', amount: -200.0)]),
          request: req,
        ),
      ]);
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.fetchLatestPayment();

      expect(result, isNotNull);
      expect(result!.entryNo, 2001);
      expect(result.currencyCode, 'AED');
      expect(result.amount, -200.0);
    });

    test('empty payment data returns null', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(200, _envelope(const []), request: req),
      ]);
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.fetchLatestPayment();

      expect(result, isNull);
    });

    test('retrying after success issues a brand-new live request', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope([_entryJson(2001)]), request: req),
        (req) async =>
            _jsonResponse(200, _envelope([_entryJson(2002)]), request: req),
      ]);
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final first = await service.fetchLatestPayment();
      final second = await service.fetchLatestPayment();

      expect(fakeHttp.requestCount, 2);
      expect(first!.entryNo, 2001);
      expect(second!.entryNo, 2002);
    });

    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      await expectLater(
        service.fetchLatestPayment(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(coordinator.handleUnauthorizedCallCount, 1);
    });

    test('HTTP 502 maps to BusinessCentralUpstreamFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      try {
        await service.fetchLatestPayment();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralUpstreamFailure>());
      }
    });

    test('HTTP 503 maps to BusinessCentralTemporarilyUnavailable', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(503, const {}, request: req),
      ]);
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      try {
        await service.fetchLatestPayment();
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
      final service = LastPaymentService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      try {
        await service.fetchLatestPayment();
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
        final service = LastPaymentService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        try {
          await service.fetchLatestPayment();
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
        final service = LastPaymentService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: coordinator,
        );

        await expectLater(
          service.fetchLatestPayment(),
          throwsA(isA<BusinessCentralFailureException>()),
        );
        expect(coordinator.handleUnauthorizedCallCount, 0);
      },
    );
  });
}
