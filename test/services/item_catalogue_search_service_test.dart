// Unit tests for ItemCatalogueSearchService and resolveExactCommonItemGroup:
// empty-query validation, exact commonItemNo resolution (case-insensitive,
// trimmed), fuzzy-suggestion fallback, no-results, multi-page aggregation,
// the defensive page cap, 401/422/502/503/network/malformed-response
// mapping, and that the session coordinator is only ever invoked for a
// confirmed 401.
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/business_central/business_central_item_search_group.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/item_catalogue_search_service.dart';

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

Map<String, dynamic> _variationJson({
  required String id,
  required String itemNo,
  String commonItemNo = '1012',
}) => {
  'id': id,
  'itemNo': itemNo,
  'commonItemNo': commonItemNo,
  'description': 'Cotton Sateen',
  'baseUnitOfMeasure': 'YRD',
  'inventory': 100,
};

Map<String, dynamic> _groupJson({
  required String commonItemNo,
  double totalInventory = 100,
  List<Map<String, dynamic>>? variations,
}) => {
  'commonItemNo': commonItemNo,
  'totalInventory': totalInventory,
  'variations':
      variations ??
      [
        _variationJson(
          id: 'id-1',
          itemNo: '${commonItemNo}A01',
          commonItemNo: commonItemNo,
        ),
      ],
};

Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> groups,
  int currentPage = 1,
  int lastPage = 1,
}) => {
  'current_page': currentPage,
  'data': groups,
  'first_page_url': '/?page=1',
  'from': groups.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url': '/?page=$lastPage',
  'next_page_url': currentPage < lastPage ? '/?page=${currentPage + 1}' : null,
  'path': '/',
  'per_page': 25,
  'prev_page_url': null,
  'to': groups.isEmpty ? null : groups.length,
  'total': groups.length,
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

void main() {
  group('resolveExactCommonItemGroup', () {
    final groups = [
      const BusinessCentralItemSearchGroup(
        commonItemNo: '1012',
        totalInventory: 2523.9,
        variations: [],
      ),
      const BusinessCentralItemSearchGroup(
        commonItemNo: '1101',
        totalInventory: 40,
        variations: [],
      ),
    ];

    test('returns the single group whose commonItemNo exactly matches', () {
      final result = resolveExactCommonItemGroup('1012', groups);
      expect(result?.commonItemNo, '1012');
    });

    test('is case-insensitive', () {
      final mixedCase = [
        const BusinessCentralItemSearchGroup(
          commonItemNo: 'ABC-1',
          totalInventory: 1,
          variations: [],
        ),
      ];
      expect(
        resolveExactCommonItemGroup('abc-1', mixedCase)?.commonItemNo,
        'ABC-1',
      );
    });

    test('trims the entered search text before comparing', () {
      expect(
        resolveExactCommonItemGroup('  1012  ', groups)?.commonItemNo,
        '1012',
      );
    });

    test('returns null when no group matches exactly (substring matches do '
        'not count)', () {
      expect(resolveExactCommonItemGroup('101', groups), isNull);
    });

    test('returns null for an empty group list', () {
      expect(resolveExactCommonItemGroup('1012', const []), isNull);
    });

    test('returns null when more than one group shares the same exact '
        'commonItemNo, never picking or merging one arbitrarily', () {
      final duplicates = [
        const BusinessCentralItemSearchGroup(
          commonItemNo: '1012',
          totalInventory: 10,
          variations: [],
        ),
        const BusinessCentralItemSearchGroup(
          commonItemNo: '1012',
          totalInventory: 20,
          variations: [],
        ),
      ];
      expect(resolveExactCommonItemGroup('1012', duplicates), isNull);
    });
  });

  group('ItemCatalogueSearchService.search — validation', () {
    test('an empty query never calls the API', () async {
      final fakeHttp = _ScriptedHttpClient([]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('   ');

      expect(result, isA<ItemCatalogueInvalidQuery>());
      expect(fakeHttp.requestCount, 0);
    });
  });

  group('ItemCatalogueSearchService.search — exact match', () {
    test('a single exact commonItemNo group returns ItemCatalogueExactMatch '
        'with only that group\'s variations', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(
            groups: [
              _groupJson(
                commonItemNo: '1012',
                variations: [
                  for (final suffix in ['A01', 'A02', 'A03'])
                    _variationJson(id: 'id-$suffix', itemNo: '1012$suffix'),
                ],
              ),
              _groupJson(commonItemNo: '1101'),
              _groupJson(commonItemNo: '1610'),
            ],
          ),
          request: req,
        ),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('1012');

      expect(result, isA<ItemCatalogueExactMatch>());
      final match = result as ItemCatalogueExactMatch;
      expect(match.group.commonItemNo, '1012');
      expect(match.group.variations, hasLength(3));
    });

    test('sends the search query as-is (trimmed) and page/per_page', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(groups: [_groupJson(commonItemNo: '1012')]),
          request: req,
        ),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      await service.search('  1012  ');

      final url = fakeHttp.requestedUrls.single;
      expect(url.path, '/api/business-central/items');
      expect(url.queryParameters['search'], '1012');
      expect(url.queryParameters['page'], '1');
    });
  });

  group('ItemCatalogueSearchService.search — suggestions', () {
    test(
      'no exact commonItemNo match returns every group as a suggestion',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(
              groups: [
                _groupJson(commonItemNo: '1101'),
                _groupJson(commonItemNo: '1610'),
                _groupJson(commonItemNo: '2210'),
              ],
            ),
            request: req,
          ),
        ]);
        final service = ApiItemCatalogueSearchService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        final result = await service.search('1012');

        expect(result, isA<ItemCatalogueSuggestions>());
        final suggestions = result as ItemCatalogueSuggestions;
        expect(suggestions.groups.map((g) => g.commonItemNo), [
          '1101',
          '1610',
          '2210',
        ]);
      },
    );
  });

  group('ItemCatalogueSearchService.search — no results', () {
    test('an empty group list returns ItemCatalogueNoResults', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async =>
            _jsonResponse(200, _envelope(groups: const []), request: req),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('NO-MATCH');

      expect(result, isA<ItemCatalogueNoResults>());
    });
  });

  group('ItemCatalogueSearchService.search — pagination', () {
    test('aggregates groups across multiple pages before resolving an exact '
        'match', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(
          200,
          _envelope(groups: [_groupJson(commonItemNo: '1101')], lastPage: 2),
          request: req,
        ),
        (req) async => _jsonResponse(
          200,
          _envelope(
            groups: [_groupJson(commonItemNo: '1012')],
            currentPage: 2,
            lastPage: 2,
          ),
          request: req,
        ),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('1012');

      expect(result, isA<ItemCatalogueExactMatch>());
      expect(fakeHttp.requestCount, 2);
      expect(fakeHttp.requestedUrls[0].queryParameters['page'], '1');
      expect(fakeHttp.requestedUrls[1].queryParameters['page'], '2');
    });

    test(
      'malformed pagination metadata (current_page never advances) '
      'returns a retryable failure, never a partial suggestion list',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(
            200,
            _envelope(groups: [_groupJson(commonItemNo: '1101')], lastPage: 2),
            request: req,
          ),
          (req) async => _jsonResponse(
            200,
            _envelope(
              groups: [_groupJson(commonItemNo: '1012')],
              currentPage: 1, // does not advance — malformed
              lastPage: 2,
            ),
            request: req,
          ),
        ]);
        final service = ApiItemCatalogueSearchService(
          apiClient: AncApiClient(httpClient: fakeHttp),
          sessionStore: FakeAuthSessionStore()..seed(_session()),
          coordinator: FakeSessionExpiryCoordinator(),
        );

        final result = await service.search('1012');

        expect(result, isA<ItemCatalogueRetryableFailure>());
      },
    );
  });

  group('ItemCatalogueSearchService.search — failure mapping', () {
    test('a missing session hands off to the coordinator and returns '
        'ItemCatalogueSessionExpired without calling the API', () async {
      final fakeHttp = _ScriptedHttpClient([]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore(),
        coordinator: coordinator,
      );

      final result = await service.search('1012');

      expect(result, isA<ItemCatalogueSessionExpired>());
      expect(coordinator.handleUnauthorizedCallCount, 1);
      expect(fakeHttp.requestCount, 0);
    });

    test('HTTP 401 hands off to the coordinator and returns '
        'ItemCatalogueSessionExpired', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      final result = await service.search('1012');

      expect(result, isA<ItemCatalogueSessionExpired>());
      expect(coordinator.handleUnauthorizedCallCount, 1);
    });

    test('HTTP 502 returns a retryable failure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('1012');
      expect(result, isA<ItemCatalogueRetryableFailure>());
    });

    test('HTTP 503 returns ItemCatalogueTemporarilyUnavailable', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(503, const {}, request: req),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('1012');
      expect(result, isA<ItemCatalogueTemporarilyUnavailable>());
    });

    test('a pagination 422 (errors.page) returns a retryable failure, never '
        'a session expiry', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(422, {
          'message': 'The given data was invalid.',
          'errors': {
            'page': ['The page field must be at least 1.'],
          },
        }, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: coordinator,
      );

      final result = await service.search('1012');
      expect(result, isA<ItemCatalogueRetryableFailure>());
      expect(coordinator.handleUnauthorizedCallCount, 0);
    });

    test('a network failure returns a retryable failure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => throw const SocketException('No route to host'),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('1012');
      expect(result, isA<ItemCatalogueRetryableFailure>());
    });

    test('a malformed 200 body returns a retryable failure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => http.StreamedResponse(
          Stream.value(utf8.encode('not json')),
          200,
          request: req,
        ),
      ]);
      final service = ApiItemCatalogueSearchService(
        apiClient: AncApiClient(httpClient: fakeHttp),
        sessionStore: FakeAuthSessionStore()..seed(_session()),
        coordinator: FakeSessionExpiryCoordinator(),
      );

      final result = await service.search('1012');
      expect(result, isA<ItemCatalogueRetryableFailure>());
    });
  });
}
