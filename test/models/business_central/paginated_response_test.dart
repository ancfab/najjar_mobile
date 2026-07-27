// Unit tests for PaginatedResponse<T>: valid envelope parsing, nullable
// from/to/next/prev handling, rejection of malformed shapes, and the
// hasNextPage/isLastPage derived properties.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/paginated_response.dart';

Map<String, dynamic> _row(int id) => {'id': id};

int _parseRow(Map<String, dynamic> json) => json['id'] as int;

Map<String, dynamic> _envelope({
  int currentPage = 1,
  List<Map<String, dynamic>>? data,
  int? from = 1,
  int lastPage = 1,
  String? nextPageUrl,
  String? prevPageUrl,
  int? to = 1,
  int total = 1,
}) => {
  'current_page': currentPage,
  'data': data ?? [_row(1)],
  'first_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
  'from': from,
  'last_page': lastPage,
  'last_page_url':
      'https://api.ancfab.com/api/business-central/ledger-entries?page=$lastPage',
  'next_page_url': nextPageUrl,
  'path': 'https://api.ancfab.com/api/business-central/ledger-entries',
  'per_page': 25,
  'prev_page_url': prevPageUrl,
  'to': to,
  'total': total,
};

void main() {
  group('PaginatedResponse.fromJson', () {
    test('parses a valid single-page envelope', () {
      final response = PaginatedResponse<int>.fromJson(_envelope(), _parseRow);

      expect(response.currentPage, 1);
      expect(response.data, [1]);
      expect(response.from, 1);
      expect(response.to, 1);
      expect(response.lastPage, 1);
      expect(response.perPage, 25);
      expect(response.total, 1);
      expect(response.nextPageUrl, isNull);
      expect(response.prevPageUrl, isNull);
    });

    test('parses empty data with null from/to', () {
      final response = PaginatedResponse<int>.fromJson(
        _envelope(data: const [], from: null, to: null, total: 0),
        _parseRow,
      );

      expect(response.data, isEmpty);
      expect(response.from, isNull);
      expect(response.to, isNull);
    });

    test('parses a populated next_page_url and prev_page_url', () {
      final response = PaginatedResponse<int>.fromJson(
        _envelope(
          currentPage: 2,
          lastPage: 3,
          nextPageUrl:
              'https://api.ancfab.com/api/business-central/ledger-entries?page=3',
          prevPageUrl:
              'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
        ),
        _parseRow,
      );

      expect(
        response.nextPageUrl,
        'https://api.ancfab.com/api/business-central/ledger-entries?page=3',
      );
      expect(
        response.prevPageUrl,
        'https://api.ancfab.com/api/business-central/ledger-entries?page=1',
      );
    });

    test('supports a total greater than one page', () {
      final response = PaginatedResponse<int>.fromJson(
        _envelope(
          currentPage: 1,
          lastPage: 4,
          total: 100,
          nextPageUrl: 'https://api.ancfab.com/x?page=2',
        ),
        _parseRow,
      );

      expect(response.total, 100);
      expect(response.lastPage, 4);
      expect(response.hasNextPage, isTrue);
      expect(response.isLastPage, isFalse);
    });

    test('rejects a non-object JSON value', () {
      expect(
        () => PaginatedResponse<int>.fromJson('not an object', _parseRow),
        throwsFormatException,
      );
    });

    test('rejects a missing data field', () {
      final json = _envelope()..remove('data');
      expect(
        () => PaginatedResponse<int>.fromJson(json, _parseRow),
        throwsFormatException,
      );
    });

    test('rejects a non-array data field', () {
      final json = _envelope();
      json['data'] = {'not': 'an array'};
      expect(
        () => PaginatedResponse<int>.fromJson(json, _parseRow),
        throwsFormatException,
      );
    });

    test('rejects a non-object row inside data', () {
      final json = _envelope();
      json['data'] = ['not an object'];
      expect(
        () => PaginatedResponse<int>.fromJson(json, _parseRow),
        throwsFormatException,
      );
    });

    test('rejects a missing required pagination field', () {
      final json = _envelope()..remove('current_page');
      expect(
        () => PaginatedResponse<int>.fromJson(json, _parseRow),
        throwsFormatException,
      );
    });
  });

  group('hasNextPage / isLastPage', () {
    test('hasNextPage is false when next_page_url is null', () {
      final response = PaginatedResponse<int>.fromJson(
        _envelope(nextPageUrl: null),
        _parseRow,
      );
      expect(response.hasNextPage, isFalse);
    });

    test('hasNextPage is true when next_page_url is present', () {
      final response = PaginatedResponse<int>.fromJson(
        _envelope(nextPageUrl: 'https://api.ancfab.com/x?page=2'),
        _parseRow,
      );
      expect(response.hasNextPage, isTrue);
    });

    test('isLastPage is true when current_page == last_page', () {
      final response = PaginatedResponse<int>.fromJson(
        _envelope(currentPage: 3, lastPage: 3),
        _parseRow,
      );
      expect(response.isLastPage, isTrue);
    });

    test('isLastPage is false when current_page < last_page', () {
      final response = PaginatedResponse<int>.fromJson(
        _envelope(currentPage: 1, lastPage: 3),
        _parseRow,
      );
      expect(response.isLastPage, isFalse);
    });
  });
}
