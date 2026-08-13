// Unit tests for CurrentBalanceService/computeCurrentBalance: the confirmed
// Current Balance calculation (Remaining_Amount summed over Open==true
// entries whose Document_Type is one of the six confirmed values), full
// pagination via LedgerEntriesService, pagination-loop protection, currency
// consistency, and the shared 401/502/503/network/malformed error mapping.
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/business_central/ledger_entry.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/current_balance_service.dart';
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
  String documentType = 'Invoice',
  bool open = true,
  double amount = 999.0,
  double remainingAmount = 100.0,
  String? currencyCode = 'USD',
}) => {
  'Entry_No': entryNo,
  'Posting_Date': '2026-01-05',
  'Document_Type': documentType,
  'Document_No': 'DOC-$entryNo',
  'Customer_No': 'CLNT-0001',
  'Customer_Name': 'Test Customer One',
  'Currency_Code': currencyCode,
  'Amount': amount,
  'Remaining_Amount': remainingAmount,
  'Due_Date': '2026-01-15',
  'Open': open,
};

LedgerEntry _entry(
  int entryNo, {
  String documentType = 'Invoice',
  bool open = true,
  double amount = 999.0,
  double remainingAmount = 100.0,
  String currencyCode = 'USD',
}) => LedgerEntry.fromJson(
  _entryJson(
    entryNo,
    documentType: documentType,
    open: open,
    amount: amount,
    remainingAmount: remainingAmount,
    currencyCode: currencyCode,
  ),
);

Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> rows,
  int currentPage = 1,
  int lastPage = 1,
  String? nextPageUrl,
}) => {
  'current_page': currentPage,
  'data': rows,
  'first_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
  'from': rows.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=$lastPage',
  'next_page_url': nextPageUrl,
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

/// Always answers with a fresh next_page_url of its own choosing,
/// simulating a backend pagination bug where `next_page_url` never becomes
/// `null`.
class _InfiniteLoopHttpClient extends http.BaseClient {
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestCount++;
    return _jsonResponse(
      200,
      _envelope(
        rows: [_entryJson(requestCount)],
        currentPage: requestCount,
        lastPage: requestCount + 1,
        nextPageUrl:
            'https://api.ancfab.com/api/business-central/ledger-entries?page=${requestCount + 1}',
      ),
      request: req,
    );
  }

  @override
  void close() {}
}

CurrentBalanceService _serviceWith(http.Client fakeHttp, {int maxPages = 500}) {
  return CurrentBalanceService(
    ledgerEntriesService: LedgerEntriesService(
      apiClient: AncApiClient(httpClient: fakeHttp),
      sessionStore: FakeAuthSessionStore()..seed(_session()),
      coordinator: FakeSessionExpiryCoordinator(),
    ),
    maxPages: maxPages,
  );
}

void main() {
  group('computeCurrentBalance', () {
    test('sums Remaining_Amount for Open entries with a relevant '
        'Document_Type', () {
      final entries = [
        _entry(1, documentType: 'Invoice', remainingAmount: 100.0),
        _entry(2, documentType: 'Payment', remainingAmount: -40.0),
      ];

      final result = computeCurrentBalance(entries);

      expect(result.amount, 60.0);
    });

    test('ignores Open == false entries', () {
      final entries = [
        _entry(1, open: true, remainingAmount: 100.0),
        _entry(2, open: false, remainingAmount: 500.0),
      ];

      final result = computeCurrentBalance(entries);

      expect(result.amount, 100.0);
    });

    test('ignores an unsupported Document_Type', () {
      final entries = [
        _entry(1, documentType: 'Invoice', remainingAmount: 100.0),
        _entry(2, documentType: 'Journal', remainingAmount: 5000.0),
      ];

      final result = computeCurrentBalance(entries);

      expect(result.amount, 100.0);
    });

    for (final type in kCurrentBalanceRelevantDocumentTypes) {
      test('includes the confirmed Document_Type "$type"', () {
        final entries = [_entry(1, documentType: type, remainingAmount: 42.0)];
        expect(computeCurrentBalance(entries).amount, 42.0);
      });
    }

    test('never uses Amount, only Remaining_Amount', () {
      final entries = [_entry(1, amount: 999.0, remainingAmount: 42.0)];
      expect(computeCurrentBalance(entries).amount, 42.0);
    });

    test('retains the exact sign of a positive Remaining_Amount', () {
      final entries = [_entry(1, remainingAmount: 250.0)];
      expect(computeCurrentBalance(entries).amount, 250.0);
    });

    test('retains the exact sign of a negative Remaining_Amount', () {
      final entries = [_entry(1, remainingAmount: -250.0)];
      expect(computeCurrentBalance(entries).amount, -250.0);
    });

    test('a mixed-sign example produces the correct net balance', () {
      final entries = [
        _entry(1, documentType: 'Invoice', remainingAmount: 500.0),
        _entry(2, documentType: 'Payment', remainingAmount: -300.0),
        _entry(3, documentType: 'Credit Memo', remainingAmount: -50.0),
        _entry(4, documentType: 'Refund', remainingAmount: 25.0),
      ];

      expect(computeCurrentBalance(entries).amount, 175.0);
    });

    test('no entries at all produces a zero balance', () {
      final result = computeCurrentBalance(const []);
      expect(result.amount, 0.0);
      expect(result.currencyCode, isNull);
    });

    test('entries present but none relevant produces a zero balance', () {
      final entries = [
        _entry(1, open: false, remainingAmount: 999.0),
        _entry(2, documentType: 'Journal', remainingAmount: 999.0),
      ];
      expect(computeCurrentBalance(entries).amount, 0.0);
    });

    test('a single nonblank Currency_Code is returned as-is', () {
      final entries = [_entry(1, currencyCode: 'AED')];
      expect(computeCurrentBalance(entries).currencyCode, 'AED');
    });

    test('a blank Currency_Code on the only entry yields a null currency', () {
      final entry = LedgerEntry.fromJson(_entryJson(1, currencyCode: null));
      expect(computeCurrentBalance([entry]).currencyCode, isNull);
    });

    test(
      'multiple relevant entries sharing one nonblank currency are fine',
      () {
        final entries = [
          _entry(1, currencyCode: 'AED', remainingAmount: 10.0),
          _entry(2, currencyCode: 'AED', remainingAmount: 20.0),
        ];
        final result = computeCurrentBalance(entries);
        expect(result.currencyCode, 'AED');
        expect(result.amount, 30.0);
      },
    );

    test('more than one distinct nonblank currency throws '
        'CurrentBalanceInconsistentCurrencyException', () {
      final entries = [
        _entry(1, currencyCode: 'AED'),
        _entry(2, currencyCode: 'USD'),
      ];
      expect(
        () => computeCurrentBalance(entries),
        throwsA(isA<CurrentBalanceInconsistentCurrencyException>()),
      );
    });

    test(
      'a blank currency alongside one nonblank currency is not inconsistent',
      () {
        final entries = [
          _entry(1, currencyCode: 'AED', remainingAmount: 10.0),
          LedgerEntry.fromJson(
            _entryJson(2, currencyCode: null, remainingAmount: 5.0),
          ),
        ];
        final result = computeCurrentBalance(entries);
        expect(result.currencyCode, 'AED');
        expect(result.amount, 15.0);
      },
    );

    test('a non-relevant entry with a different currency is excluded from '
        'the consistency check', () {
      final entries = [
        _entry(1, documentType: 'Invoice', currencyCode: 'AED'),
        _entry(2, documentType: 'Journal', currencyCode: 'USD'),
      ];
      expect(computeCurrentBalance(entries).currencyCode, 'AED');
    });
  });

  group('CurrentBalanceService.fetchCurrentBalance', () {
    test(
      'requests page 1 of GET /api/business-central/ledger-entries',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_entryJson(1001)]),
            request: req,
          ),
        ]);
        final service = _serviceWith(fakeHttp);

        await service.fetchCurrentBalance();

        expect(fakeHttp.requestCount, 1);
        expect(
          fakeHttp.requestedUrls.single.path,
          '/api/business-central/ledger-entries',
        );
        expect(fakeHttp.requestedUrls.single.queryParameters['page'], '1');
      },
    );

    test('fetches every page until next_page_url is null', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(1, remainingAmount: 10.0)],
            lastPage: 3,
            nextPageUrl:
                'https://api.ancfab.com/api/business-central/ledger-entries?page=2',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(2, remainingAmount: 20.0)],
            currentPage: 2,
            lastPage: 3,
            nextPageUrl:
                'https://api.ancfab.com/api/business-central/ledger-entries?page=3',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(3, remainingAmount: 30.0)],
            currentPage: 3,
            lastPage: 3,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      final result = await service.fetchCurrentBalance();

      expect(fakeHttp.requestCount, 3);
      expect(result.amount, 60.0);
    });

    test('does not calculate from page 1 only when more pages exist', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(1, remainingAmount: 10.0)],
            lastPage: 2,
            nextPageUrl:
                'https://api.ancfab.com/api/business-central/ledger-entries?page=2',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(2, remainingAmount: 90.0)],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      final result = await service.fetchCurrentBalance();

      expect(result.amount, 100.0);
    });

    test(
      'stops once hasNextPage is false (page count matches page total)',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(rows: [_entryJson(1)]),
            request: req,
          ),
        ]);
        final service = _serviceWith(fakeHttp);

        await service.fetchCurrentBalance();

        expect(fakeHttp.requestCount, 1);
      },
    );

    test(
      'duplicate Entry_No rows across a page boundary are not double-counted',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [_entryJson(1001, remainingAmount: 50.0)],
              lastPage: 2,
              nextPageUrl:
                  'https://api.ancfab.com/api/business-central/ledger-entries?page=2',
            ),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            // The backend repeats the boundary record 1001.
            _envelope(
              rows: [
                _entryJson(1001, remainingAmount: 50.0),
                _entryJson(1002, remainingAmount: 25.0),
              ],
              currentPage: 2,
              lastPage: 2,
            ),
            request: req,
          ),
        ]);
        final service = _serviceWith(fakeHttp);

        final result = await service.fetchCurrentBalance();

        expect(result.amount, 75.0);
      },
    );

    test('a pagination loop (next_page_url never null) is stopped by the '
        'maxPages cap instead of hanging forever', () async {
      final fakeHttp = _InfiniteLoopHttpClient();
      final service = _serviceWith(fakeHttp, maxPages: 3);

      await service.fetchCurrentBalance();

      expect(fakeHttp.requestCount, 3);
    });

    test('reproduces the reported production bug: page 1 reports '
        'next_page_url "/?page=2" (a bare, path-dropping URL) and pagination '
        'still succeeds across all 4 pages by requesting page numbers '
        'directly, never throwing ArgumentError', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(1, remainingAmount: 10.0)],
            currentPage: 1,
            lastPage: 4,
            nextPageUrl: '/?page=2',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(2, remainingAmount: 20.0)],
            currentPage: 2,
            lastPage: 4,
            nextPageUrl: '/?page=3',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(3, remainingAmount: 30.0)],
            currentPage: 3,
            lastPage: 4,
            nextPageUrl: '/?page=4',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(4, remainingAmount: 40.0)],
            currentPage: 4,
            lastPage: 4,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      final result = await service.fetchCurrentBalance();

      expect(fakeHttp.requestCount, 4);
      expect(result.amount, 100.0);
      for (final url in fakeHttp.requestedUrls) {
        expect(url.host, 'api.ancfab.com');
        expect(url.path, '/api/business-central/ledger-entries');
      }
      expect(fakeHttp.requestedUrls[0].queryParameters['page'], '1');
      expect(fakeHttp.requestedUrls[1].queryParameters['page'], '2');
      expect(fakeHttp.requestedUrls[2].queryParameters['page'], '3');
      expect(fakeHttp.requestedUrls[3].queryParameters['page'], '4');
    });

    test('a malformed (non-advancing) page partway through pagination never '
        'returns a partial balance', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [_entryJson(1, remainingAmount: 10.0)],
            lastPage: 3,
            nextPageUrl: '/?page=2',
          ),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          // Malformed: still reports current_page 1 despite page=2 being
          // requested — must not be summed into the balance.
          _envelope(
            rows: [_entryJson(2, remainingAmount: 99999.0)],
            currentPage: 1,
            lastPage: 3,
          ),
          request: req,
        ),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchCurrentBalance();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralProtocolFailure>());
      }
    });

    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = CurrentBalanceService(
        ledgerEntriesService: LedgerEntriesService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: coordinator,
        ),
      );

      await expectLater(
        service.fetchCurrentBalance(),
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
        await service.fetchCurrentBalance();
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
        await service.fetchCurrentBalance();
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
        await service.fetchCurrentBalance();
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
          await service.fetchCurrentBalance();
          fail('Expected a BusinessCentralFailureException');
        } on BusinessCentralFailureException catch (error) {
          expect(error.outcome, isA<BusinessCentralProtocolFailure>());
        }
      },
    );

    test(
      'an inconsistent-currency response throws after fetching all pages',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [_entryJson(1, currencyCode: 'AED')],
              lastPage: 2,
              nextPageUrl:
                  'https://api.ancfab.com/api/business-central/ledger-entries?page=2',
            ),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [_entryJson(2, currencyCode: 'USD')],
              currentPage: 2,
              lastPage: 2,
            ),
            request: req,
          ),
        ]);
        final service = _serviceWith(fakeHttp);

        await expectLater(
          service.fetchCurrentBalance(),
          throwsA(isA<CurrentBalanceInconsistentCurrencyException>()),
        );
      },
    );
  });
}
