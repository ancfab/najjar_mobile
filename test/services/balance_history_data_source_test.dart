// Unit tests for LedgerBalanceHistoryDataSource: the live ledger-entries
// pipeline (page 1..N via LedgerEntriesService), the historical-balance
// reconstruction graph (opening balance, chronological signed-Amount
// application, same-day aggregation, inclusive Posting_Date boundaries),
// currency consistency, pagination across multiple pages, and error
// propagation — no mock/fabricated data anywhere in this path.
//
// Balance History is graph-only (BalanceHistoryData carries no transaction
// list — see that class's doc comment); Quick History owns the individual
// ledger-transaction adapter/UI and is covered by its own tests.
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/balance_history_data_source.dart';
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

Map<String, dynamic> _entryJson(
  int entryNo, {
  String postingDate = '2026-01-05',
  String documentType = 'Invoice',
  String documentNo = 'DOC',
  bool open = true,
  double amount = 100.0,
  String? currencyCode = 'USD',
}) {
  final no = '$documentNo-$entryNo';
  return {
    'Entry_No': entryNo,
    'Posting_Date': postingDate,
    'Document_Type': documentType,
    'Document_No': no,
    'Customer_No': 'CLNT-0001',
    'Customer_Name': 'Test Customer One',
    'Currency_Code': currencyCode,
    'Amount': amount,
    'Remaining_Amount': amount,
    'Due_Date': '2026-01-15',
    'Open': open,
  };
}

Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> rows,
  int currentPage = 1,
  int lastPage = 1,
}) => {
  'current_page': currentPage,
  'data': rows,
  'first_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
  'from': rows.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=$lastPage',
  'next_page_url': currentPage < lastPage
      ? 'https://api.ancfab.com/api/business-central/ledger-entries?page=${currentPage + 1}'
      : null,
  'path': 'https://api.ancfab.com/api/business-central/ledger-entries',
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

/// Serves one scripted response per request, in call order.
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

LedgerBalanceHistoryDataSource _sourceWith(http.Client fakeHttp) {
  return LedgerBalanceHistoryDataSource(
    ledgerEntriesService: LedgerEntriesService(
      apiClient: AncApiClient(httpClient: fakeHttp),
      sessionStore: FakeAuthSessionStore()..seed(_session()),
      coordinator: FakeSessionExpiryCoordinator(),
    ),
  );
}

void main() {
  group('Production default (no mock reaches the real app)', () {
    test('AccountBalanceScreen defaults to LedgerBalanceHistoryDataSource — '
        'MockBalanceHistoryDataSource/kMockBalanceHistoryByRange no longer '
        'exist in production code', () {
      final screen = AccountBalanceScreen();
      expect(
        screen.balanceHistorySource,
        isA<LedgerBalanceHistoryDataSource>(),
      );
    });
  });

  group('Posting_Date range filtering (graph)', () {
    test('an entry exactly on the From date has no separate opening point — '
        'the single point is the post-entry balance (inclusive lower '
        'boundary)', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_entryJson(1, postingDate: '2026-01-01')]),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points, hasLength(1));
      expect(result.points.single.date, DateTime(2026, 1, 1));
      expect(result.points.single.balance, 100.0);
    });

    test('an entry exactly on the To date is still applied in the walk '
        '(inclusive upper boundary), as a second point after the opening '
        'balance', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_entryJson(1, postingDate: '2026-01-31')]),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points, hasLength(2));
      expect(result.points.first.date, DateTime(2026, 1, 1));
      expect(result.points.first.balance, 0.0);
      expect(result.points.last.date, DateTime(2026, 1, 31));
      expect(result.points.last.balance, 100.0);
    });

    test('an entry posted one day before From is not plotted as its own '
        'point, but is still carried forward into the opening balance — '
        'never dropped from the accounting', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_entryJson(1, postingDate: '2025-12-31')]),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points, hasLength(1));
      expect(result.points.single.date, DateTime(2026, 1, 1));
      expect(result.points.single.balance, 100.0);
    });

    test('an entry posted one day after To is excluded from the walk — the '
        'visible range never reflects a movement outside it', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_entryJson(1, postingDate: '2026-02-01')]),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points, hasLength(1));
      expect(result.points.single.date, DateTime(2026, 1, 1));
      expect(result.points.single.balance, 0.0);
    });

    test('a time-of-day component on From/To never excludes a boundary '
        'entry (date-only comparison)', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_entryJson(1, postingDate: '2026-01-01')]),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      // Simulates a From value with a non-midnight time component.
      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1, 23, 59, 59),
        to: DateTime(2026, 1, 31, 0, 0, 1),
      );

      expect(result.points, hasLength(1));
      expect(result.points.single.date, DateTime(2026, 1, 1));
    });

    test('a range with no relevant entries inside it still plots the '
        'carried-forward balance as of From — never an empty graph and '
        'never a reset to zero', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(1, postingDate: '2025-01-01'),
              _entryJson(2, postingDate: '2027-01-01'),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      // currentBalance (both open) = 200; only entry 2 (2027) is >= From,
      // so openingBalance = 200 - 100 = 100 — the pre-From entry's effect is
      // still reflected, never dropped and never zeroed out.
      expect(result.points, hasLength(1));
      expect(result.points.single.date, DateTime(2026, 1, 1));
      expect(result.points.single.balance, 100.0);
    });
  });

  group('Currency consistency', () {
    test(
      'blocks the graph (empty points, null currencyCode) when the range '
      'spans multiple distinct nonblank Currency_Codes — never summed',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _entryJson(1, postingDate: '2026-01-05', currencyCode: 'AED'),
                _entryJson(2, postingDate: '2026-01-10', currencyCode: 'USD'),
                _entryJson(3, postingDate: '2026-01-15', currencyCode: null),
              ],
            ),
            request: req,
          ),
        ]);
        final source = _sourceWith(fakeHttp);

        final result = await source.fetchBalanceHistory(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 1, 31),
        );

        // AED + USD among relevant entries — the graph cannot combine two
        // currencies into one balance series. A blank Currency_Code never
        // counts as a distinct currency.
        expect(result.hasMultipleCurrencies, isTrue);
        expect(result.points, isEmpty);
        expect(result.currencyCode, isNull);
      },
    );
  });

  group('Historical balance reconstruction (graph)', () {
    // A fully-settled Invoice+Payment pair (net zero, both closed) followed
    // by a still-open Invoice — the same worked example verified by hand in
    // this class's own doc comment: computeCurrentBalance (Remaining_Amount
    // over Open==true) gives 500 (only the open Invoice), and it must equal
    // the last graph point when the range extends through today (no
    // relevant entries exist after the fixture's latest posting date).
    List<Map<String, dynamic>> settledPairPlusOpenInvoice() => [
      _entryJson(
        1,
        postingDate: '2026-01-01',
        documentType: 'Invoice',
        amount: 1000.0,
        open: false,
      ),
      _entryJson(
        2,
        postingDate: '2026-01-10',
        documentType: 'Payment',
        amount: -1000.0,
        open: false,
      ),
      _entryJson(
        3,
        postingDate: '2026-01-20',
        documentType: 'Invoice',
        amount: 500.0,
        open: true,
      ),
    ];

    test('the last point equals the authoritative computeCurrentBalance value '
        'when the range extends through the latest posting date', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: settledPairPlusOpenInvoice()),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points.last.balance, 500.0);
    });

    test('applies positive and negative movements chronologically, oldest '
        'point first', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: settledPairPlusOpenInvoice()),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      // From (Jan 1) itself has an entry, so no separate opening point —
      // the first point is Jan 1's own resulting balance (+1000).
      expect(result.points.map((p) => p.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 10),
        DateTime(2026, 1, 20),
      ]);
      expect(result.points.map((p) => p.balance), [1000.0, 0.0, 500.0]);
    });

    test('the opening balance at a From date strictly between two entries is '
        'the balance after the earlier one, and is plotted as a separate '
        'point since From itself has no activity', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: settledPairPlusOpenInvoice()),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      // Jan 15 sits between the settled Payment (Jan 10) and the open
      // Invoice (Jan 20) — the balance was 0 throughout that gap.
      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 15),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points.first.date, DateTime(2026, 1, 15));
      expect(result.points.first.balance, 0.0);
      expect(result.points.last.balance, 500.0);
    });

    test(
      'a From date with its own entries has no separate opening point — '
      'the first point is the resulting balance after From\'s own entries',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: settledPairPlusOpenInvoice()),
            request: req,
          ),
        ]);
        final source = _sourceWith(fakeHttp);

        final result = await source.fetchBalanceHistory(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 1, 31),
        );

        expect(result.points.first.date, DateTime(2026, 1, 1));
        // Not the pre-Jan-1 opening balance (0) — the post-entry balance.
        expect(result.points.first.balance, 1000.0);
      },
    );

    test('multiple entries on the same Posting_Date produce exactly one point '
        'holding that day\'s final net balance', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(
                1,
                postingDate: '2026-01-05',
                documentType: 'Invoice',
                amount: 200.0,
                open: true,
              ),
              _entryJson(
                2,
                postingDate: '2026-01-05',
                documentType: 'Payment',
                amount: -50.0,
                open: true,
              ),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      // From coincides with the entries' own date, so there is no
      // separate opening-balance point to account for — isolates the
      // same-day-grouping behavior this test is about.
      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 5),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points, hasLength(1));
      expect(result.points.single.date, DateTime(2026, 1, 5));
      // Both entries applied even though only one point is drawn.
      expect(result.points.single.balance, 150.0);
    });

    test('a zero-value entry is applied without crashing and does not '
        'change the running balance', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(
                1,
                postingDate: '2026-01-05',
                documentType: 'Invoice',
                amount: 300.0,
                open: true,
              ),
              _entryJson(
                2,
                postingDate: '2026-01-10',
                documentType: 'Payment',
                amount: 0.0,
                open: false,
              ),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      // From (Jan 1) predates the first entry (Jan 5), so the opening
      // balance (0, nothing happened yet) is its own leading point.
      expect(result.points.map((p) => p.balance), [0.0, 300.0, 300.0]);
    });

    test('only the confirmed balance-relevant Document_Types feed the graph — '
        'an irrelevant type (e.g. Journal) is excluded from the balance '
        'math entirely', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(
                1,
                postingDate: '2026-01-05',
                documentType: 'Invoice',
                amount: 300.0,
                open: true,
              ),
              _entryJson(
                2,
                postingDate: '2026-01-05',
                documentType: 'Journal',
                amount: 99999.0,
                open: true,
              ),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      // From coincides with both entries' date, isolating the
      // document-type filtering this test is about from the separate
      // opening-balance-point mechanics covered elsewhere.
      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 5),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points, hasLength(1));
      expect(result.points.single.balance, 300.0);
    });

    // NOTE: computeCurrentBalance's own CurrentBalanceInconsistentCurrencyException
    // (thrown when *open* relevant entries span multiple currencies) can
    // never actually surface from fetchBalanceHistory: this class's own
    // hasMultipleCurrencies check runs first and is strictly broader (it
    // inspects every relevant entry, open or closed — see the class doc
    // comment), so any currency conflict among open entries is necessarily
    // also a conflict among all relevant entries and is caught by that
    // check first, well before computeCurrentBalance is ever called. There
    // is deliberately no test asserting the exception path here, since it
    // is unreachable through this data source.
  });

  group('Business Central blank Document_Type', () {
    test('an open blank-type (" ") entry participates in the walk exactly '
        'like a named type', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(
                1,
                postingDate: '2026-01-05',
                documentType: ' ',
                amount: 124.90,
                open: true,
              ),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points.map((p) => p.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
      ]);
      expect(result.points.first.balance, closeTo(0.0, 1e-9));
      expect(result.points.last.balance, closeTo(124.90, 1e-9));
    });

    test('a whitespace-only ("   ") blank-type entry is treated the same as '
        'a single-space blank type', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(
                1,
                postingDate: '2026-01-05',
                documentType: '   ',
                amount: 124.90,
                open: true,
              ),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points.last.balance, closeTo(124.90, 1e-9));
    });

    test('a closed blank-type entry still moves the historical walk through '
        'its Amount, even though it contributes nothing to Current Balance '
        '(open entries only) — the open/closed distinction between the two '
        'calculations', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(
                1,
                postingDate: '2026-01-05',
                documentType: ' ',
                amount: 124.90,
                open: false,
              ),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      // currentBalance = 0 (the entry is closed, so Current Balance excludes
      // it), but the walk still applies its +124.90 Amount between the
      // opening point and Jan 5 — proving it was not silently dropped from
      // history just because it is closed.
      expect(result.points.map((p) => p.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
      ]);
      expect(result.points.first.balance, closeTo(-124.90, 1e-9));
      expect(result.points.last.balance, closeTo(0.0, 1e-9));
    });

    test('reconciliation regression: the last point over a range covering '
        'all activity equals 200.94 (76.04 from named relevant entries plus '
        '124.90 from the blank-type entry) — the production identity this '
        'fix restores, never the pre-fix 76.04', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _entryJson(
                1,
                postingDate: '2026-01-05',
                documentType: 'Invoice',
                amount: 76.04,
                open: true,
              ),
              _entryJson(
                2,
                postingDate: '2026-01-10',
                documentType: ' ',
                amount: 124.90,
                open: true,
              ),
            ],
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points.last.balance, closeTo(200.94, 1e-9));
    });
  });

  group('Pagination', () {
    test('loads every page and filters the combined result set', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(1, postingDate: '2026-01-05')],
            lastPage: 2,
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(2, postingDate: '2026-01-20')],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(fakeHttp.requestCount, 2);
      // Both pages' entries participate in the walk: opening (Jan 1, 0),
      // then Jan 5's +100, then Jan 20's +100.
      expect(result.points.map((p) => p.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 20),
      ]);
      expect(result.points.last.balance, 200.0);
    });

    test('an entry on a later page outside the range still counts toward the '
        'anchor/opening-balance math, but is never plotted as an in-range '
        'point', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(1, postingDate: '2026-01-05')],
            lastPage: 2,
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(2, postingDate: '2027-06-01')],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final source = _sourceWith(fakeHttp);

      final result = await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(result.points.any((p) => p.date == DateTime(2027, 6, 1)), isFalse);
      expect(result.points.map((p) => p.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
      ]);
      // Not 200 — the 2027 entry is excluded from the visible walk even
      // though it was fetched and contributed to currentBalance/opening.
      expect(result.points.last.balance, 100.0);
    });

    test('sends only page/per_page — never an unconfirmed date query '
        'parameter', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(rows: [_entryJson(1)]), request: req),
      ]);
      final source = _sourceWith(fakeHttp);

      await source.fetchBalanceHistory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      final queryKeys = fakeHttp.requestedUrls.single.queryParameters.keys;
      expect(queryKeys, unorderedEquals(['page', 'per_page']));
    });
  });

  group('Failure propagation', () {
    test('a 502/503 upstream failure throws BusinessCentralFailureException, '
        'never falls back to mock history', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(503, const {}, request: req),
      ]);
      final source = _sourceWith(fakeHttp);

      await expectLater(
        source.fetchBalanceHistory(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 1, 31),
        ),
        throwsA(isA<BusinessCentralFailureException>()),
      );
    });

    test('a 401 throws SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final source = _sourceWith(fakeHttp);

      await expectLater(
        source.fetchBalanceHistory(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 1, 31),
        ),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });
}
