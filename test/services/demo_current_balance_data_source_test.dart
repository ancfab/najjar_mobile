// Unit tests for DemoCurrentBalanceDataSource: the TEMPORARY CLIENT DEMO
// MODE data source that must return a fixed balance with no I/O and never
// touch the live ledger-entries endpoint.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/demo_current_balance_data_source.dart';

void main() {
  group('DemoCurrentBalanceDataSource', () {
    test('fetchCurrentBalance resolves with the fixed mock balance', () async {
      const source = DemoCurrentBalanceDataSource();

      final result = await source.fetchCurrentBalance();

      expect(result.amount, 18450.75);
      expect(result.currencyCode, 'AED');
    });

    test('every call returns the same mock balance', () async {
      const source = DemoCurrentBalanceDataSource();

      final first = await source.fetchCurrentBalance();
      final second = await source.fetchCurrentBalance();

      expect(first.amount, second.amount);
      expect(first.currencyCode, second.currencyCode);
    });
  });
}
