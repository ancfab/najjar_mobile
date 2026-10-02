// Unit tests for SnapshotCurrentBalanceDataSource: the Home card's balance
// now comes from one customer-details request plus one ledger page for the
// currency, instead of a page-by-page sweep of the whole ledger.
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/customer_details_service.dart';
import 'package:anc_fabrics/services/ledger_entries_service.dart';
import 'package:anc_fabrics/services/snapshot_current_balance_data_source.dart';

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

Map<String, dynamic> _customerDetailsBody({double balance = 36711.73}) => {
  'customerbalance': balance,
  'availableCredit': 57150.00,
  'usedCredit': 42850.00,
};

Map<String, dynamic> _ledgerEntry({
  int entryNo = 1,
  String currency = 'AED',
  bool open = true,
  String documentType = 'Invoice',
}) => {
  'Entry_No': entryNo,
  'Document_Type': documentType,
  'Document_No': 'INV-$entryNo',
  'Customer_No': 'SAMPLE-0001',
  'Customer_Name': 'Sample Customer',
  'Posting_Date': '2026-09-01',
  'Due_Date': '2026-09-30',
  'Amount': 100.0,
  'Remaining_Amount': 100.0,
  'Open': open,
  'Currency_Code': currency,
};

Map<String, dynamic> _ledgerPage(List<Map<String, dynamic>> data) => {
  'data': data,
  'current_page': 1,
  'first_page_url': 'https://api.example.test/ledger-entries?page=1',
  'from': 1,
  'last_page': 3,
  'last_page_url': 'https://api.example.test/ledger-entries?page=3',
  'next_page_url': 'https://api.example.test/ledger-entries?page=2',
  'path': 'https://api.example.test/ledger-entries',
  'per_page': 100,
  'prev_page_url': null,
  'to': 1,
  'total': data.length,
};

/// Answers each request by URL, so the two parallel requests can resolve in
/// whichever order they like without the test depending on that order.
class _RoutedHttpClient extends http.BaseClient {
  _RoutedHttpClient({
    required this.customerDetails,
    required this.ledger,
  });

  final Future<http.StreamedResponse> Function(http.Request) customerDetails;
  final Future<http.StreamedResponse> Function(http.Request) ledger;

  final List<Uri> requestedUrls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestedUrls.add(req.url);
    if (req.url.path.contains('customer-details')) return customerDetails(req);
    if (req.url.path.contains('ledger-entries')) return ledger(req);
    throw StateError('unexpected request: ${req.url}');
  }

  @override
  void close() {}
}

http.StreamedResponse _json(
  int statusCode,
  Map<String, dynamic> body,
  http.Request request,
) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

SnapshotCurrentBalanceDataSource _sourceWith(http.Client fakeHttp) {
  final apiClient = AncApiClient(httpClient: fakeHttp);
  return SnapshotCurrentBalanceDataSource(
    customerDetailsService: CustomerDetailsService(
      apiClient: apiClient,
      sessionStore: FakeAuthSessionStore()..seed(_session()),
      coordinator: FakeSessionExpiryCoordinator(),
    ),
    ledgerEntriesService: LedgerEntriesService(
      apiClient: apiClient,
      sessionStore: FakeAuthSessionStore()..seed(_session()),
      coordinator: FakeSessionExpiryCoordinator(),
      perPage: 100,
    ),
  );
}

void main() {
  test('Returns the customer-details balance with the ledger currency', () async {
    final http = _RoutedHttpClient(
      customerDetails: (req) async => _json(200, _customerDetailsBody(), req),
      ledger: (req) async =>
          _json(200, _ledgerPage([_ledgerEntry()]), req),
    );

    final result = await _sourceWith(http).fetchCurrentBalance();

    expect(result.amount, 36711.73);
    expect(result.currencyCode, 'AED');
  });

  test('Reads one ledger page only, never the whole ledger', () async {
    final http = _RoutedHttpClient(
      customerDetails: (req) async => _json(200, _customerDetailsBody(), req),
      ledger: (req) async =>
          _json(200, _ledgerPage([_ledgerEntry()]), req),
    );

    await _sourceWith(http).fetchCurrentBalance();

    // Exactly two requests, although the fixture reports three ledger pages.
    expect(http.requestedUrls, hasLength(2));
    final ledgerUrls = http.requestedUrls.where(
      (url) => url.path.contains('ledger-entries'),
    );
    expect(ledgerUrls, hasLength(1));
    expect(ledgerUrls.single.queryParameters['page'], '1');
  });

  test('A failed currency lookup still yields the balance, with no currency', () async {
    final http = _RoutedHttpClient(
      customerDetails: (req) async => _json(200, _customerDetailsBody(), req),
      ledger: (req) async => _json(503, const {}, req),
    );

    final result = await _sourceWith(http).fetchCurrentBalance();

    expect(result.amount, 36711.73);
    expect(result.currencyCode, isNull);
  });

  test('No nonblank currency on the page resolves to null, never a guess', () async {
    final http = _RoutedHttpClient(
      customerDetails: (req) async => _json(200, _customerDetailsBody(), req),
      ledger: (req) async =>
          _json(200, _ledgerPage([_ledgerEntry(currency: '')]), req),
    );

    final result = await _sourceWith(http).fetchCurrentBalance();

    expect(result.currencyCode, isNull);
  });

  test('Closed and non-balance-relevant rows never supply the currency', () async {
    final http = _RoutedHttpClient(
      customerDetails: (req) async => _json(200, _customerDetailsBody(), req),
      ledger: (req) async => _json(
        200,
        _ledgerPage([
          _ledgerEntry(entryNo: 1, currency: 'USD', open: false),
          _ledgerEntry(entryNo: 2, currency: 'EUR', documentType: 'Order'),
          _ledgerEntry(entryNo: 3, currency: 'AED'),
        ]),
        req,
      ),
    );

    final result = await _sourceWith(http).fetchCurrentBalance();

    expect(result.currencyCode, 'AED');
  });

  test('A failed balance request fails the whole fetch', () async {
    final http = _RoutedHttpClient(
      customerDetails: (req) async => _json(503, const {}, req),
      ledger: (req) async =>
          _json(200, _ledgerPage([_ledgerEntry()]), req),
    );

    await expectLater(
      _sourceWith(http).fetchCurrentBalance(),
      throwsA(isA<BusinessCentralFailureException>()),
    );
  });

  test('A zero balance is returned as a real zero', () async {
    final http = _RoutedHttpClient(
      customerDetails: (req) async =>
          _json(200, _customerDetailsBody(balance: 0), req),
      ledger: (req) async =>
          _json(200, _ledgerPage([_ledgerEntry()]), req),
    );

    final result = await _sourceWith(http).fetchCurrentBalance();

    expect(result.amount, 0);
  });
}
