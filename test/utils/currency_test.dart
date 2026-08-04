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

    test(
      'formats negative amounts with a leading minus before the dollar sign',
      () {
        expect(formatCurrency(-42.5), '-\$42.50');
      },
    );

    test('formats zero', () {
      expect(formatCurrency(0), '\$0.00');
    });

    test(
      'uses the ANC API-provided currency code instead of "\$" when given',
      () {
        expect(formatCurrency(1936.5, currencyCode: 'AED'), 'AED 1,936.50');
      },
    );

    test('renders a USD currency code as "USD", not "\$"', () {
      expect(formatCurrency(100.5, currencyCode: 'USD'), 'USD 100.50');
    });

    test('does not alter the numeric value when a currency code is given', () {
      expect(formatCurrency(1936.5, currencyCode: 'AED'), contains('1,936.50'));
      expect(formatCurrency(1936.5), contains('1,936.50'));
    });

    test('a negative amount with a currency code shows a leading minus before '
        'the code', () {
      expect(formatCurrency(-42.5, currencyCode: 'AED'), '-AED 42.50');
    });

    test('falls back to "\$" when no currency code is available', () {
      expect(formatCurrency(100.5, currencyCode: null), '\$100.50');
      expect(formatCurrency(100.5), '\$100.50');
    });
  });

  group('formatCurrencyOrUnknown', () {
    test('uses the given currency code, matching formatCurrency\'s style', () {
      expect(
        formatCurrencyOrUnknown(42850.0, currencyCode: 'USD'),
        'USD 42,850.00',
      );
      expect(
        formatCurrencyOrUnknown(1936.5, currencyCode: 'AED'),
        'AED 1,936.50',
      );
    });

    test('shows "?" instead of "\$" when currencyCode is null', () {
      expect(formatCurrencyOrUnknown(100.5, currencyCode: null), '? 100.50');
    });

    test('shows "?" when currencyCode is empty', () {
      expect(formatCurrencyOrUnknown(100.5, currencyCode: ''), '? 100.50');
    });

    test('shows "?" when currencyCode is whitespace-only', () {
      expect(formatCurrencyOrUnknown(100.5, currencyCode: '   '), '? 100.50');
    });

    test('never silently defaults an unknown currency to "\$"', () {
      expect(
        formatCurrencyOrUnknown(100.5, currencyCode: null),
        isNot(contains('\$')),
      );
    });

    test('formats zero and preserves thousands grouping/decimals', () {
      expect(formatCurrencyOrUnknown(0, currencyCode: 'USD'), 'USD 0.00');
      expect(
        formatCurrencyOrUnknown(12862.50, currencyCode: 'AED'),
        'AED 12,862.50',
      );
    });

    test('a negative amount shows a leading minus before the prefix, known or '
        'unknown currency alike', () {
      expect(formatCurrencyOrUnknown(-42.5, currencyCode: 'AED'), '-AED 42.50');
      expect(formatCurrencyOrUnknown(-42.5, currencyCode: null), '-? 42.50');
    });
  });
}
