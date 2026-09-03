// Unit tests for ApiHomeDashboardService: the production HomeDashboardService
// implementation backing Home's Active Orders / Overdue Invoices metric
// cards, over a real CustomerDetailsService wired to a scripted fake
// http.Client (never the live ANC API) and a fake in-memory
// AuthSessionStore (never real secure storage).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/customer_details_service.dart';
import 'package:anc_fabrics/services/home_dashboard_service.dart';

import '../helpers/fake_auth_session_store.dart';

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

class _ScriptedHttpClient extends http.BaseClient {
  _ScriptedHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _respond(request as http.Request);
  }

  @override
  void close() {}
}

http.StreamedResponse _jsonResponse(
  int statusCode,
  Map<String, dynamic> body, {
  required http.Request request,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))),
  statusCode,
  request: request,
  headers: {'content-type': 'application/json'},
);

ApiHomeDashboardService _service(http.Client httpClient) {
  final store = FakeAuthSessionStore()..seed(_session());
  return ApiHomeDashboardService(
    customerDetailsService: CustomerDetailsService(
      apiClient: AncApiClient(httpClient: httpClient),
      sessionStore: store,
    ),
  );
}

void main() {
  group('overdueInvoicesAmount', () {
    test(
      'is a plain, unprefixed figure — never a "?" unknown-currency '
      'marker, since this field carries no currency on any tenant',
      () async {
        final http = _ScriptedHttpClient(
          (req) async => _jsonResponse(200, {
            'data': {
              'customerbalance': 100.0,
              'availableCredit': 0.0,
              'usedCredit': 0.0,
              'overdueInvoicesAmount': 1250.0,
              'activeOrders': 3,
            },
          }, request: req),
        );

        final data = await _service(http).fetchHomeDashboardData();

        expect(data.overdueInvoicesAmount, '1,250.00');
        expect(data.overdueInvoicesAmount, isNot(contains('?')));
        expect(data.activeOrdersCount, '3');
      },
    );

    test('shows the unknown placeholder, not "0", when the backend omits '
        'overdueInvoicesAmount', () async {
      final http = _ScriptedHttpClient(
        (req) async => _jsonResponse(200, {
          'data': {
            'customerbalance': 100.0,
            'availableCredit': 0.0,
            'usedCredit': 0.0,
          },
        }, request: req),
      );

      final data = await _service(http).fetchHomeDashboardData();

      expect(data.overdueInvoicesAmount, '—');
      expect(data.activeOrdersCount, '—');
    });
  });
}
