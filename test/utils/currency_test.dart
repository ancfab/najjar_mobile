import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/utils/currency.dart';

void main() {
  group('formatCurrency', () {
    test('formats amounts under 1000 with two decimals and no comma', () {
      expect(formatCurrency(850.0), '\$850.00');
    });

    test('formats four-digit amounts with a thousands comma', () {
      expect(formatCurrency(10200.0), '\$10,200.00');
      expect(formatCurrency(2050.0), '\$2,050.00');
    });

    test('formats five-digit amounts with a thousands comma', () {
      expect(formatCurrency(12250.0), '\$12,250.00');
      expect(formatCurrency(12862.50), '\$12,862.50');
    });

    test('rounds to two decimal places', () {
      expect(formatCurrency(612.5), '\$612.50');
    });

    test('formats negative amounts with a leading minus before the dollar sign', () {
      expect(formatCurrency(-42.5), '-\$42.50');
    });

    test('formats zero', () {
      expect(formatCurrency(0), '\$0.00');
    });
  });
}
