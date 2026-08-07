// Unit tests for DemoSalesOrderLinesDataSource: the TEMPORARY CLIENT DEMO
// MODE data source that must return a fixed single page with no I/O and
// never touch the live sales-orders endpoint.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/demo_sales_order_lines_data_source.dart';

void main() {
  group('DemoSalesOrderLinesDataSource', () {
    test('fetchPage resolves with the fixed mock page', () async {
      const source = DemoSalesOrderLinesDataSource();

      final result = await source.fetchPage(page: 1, perPage: 25);

      expect(result.data, DemoSalesOrderLinesDataSource.mockLines);
      expect(result.currentPage, 1);
      expect(result.lastPage, 1);
      expect(result.nextPageUrl, isNull);
      expect(result.total, DemoSalesOrderLinesDataSource.mockLines.length);
    });

    test('every call returns the same fixed page regardless of the '
        'requested page/perPage', () async {
      const source = DemoSalesOrderLinesDataSource();

      final first = await source.fetchPage(page: 1, perPage: 25);
      final second = await source.fetchPage(page: 2, perPage: 10);

      expect(first.data, second.data);
      expect(first.currentPage, second.currentPage);
    });

    test('mock lines never throw when parsed by the real row shape (sanity '
        'check that this fixture matches BusinessCentralSalesOrderLine\'s '
        'required fields)', () {
      for (final line in DemoSalesOrderLinesDataSource.mockLines) {
        expect(line.documentNo, isNotEmpty);
        expect(line.itemNo, isNotEmpty);
        expect(line.description, isNotEmpty);
      }
    });
  });
}
