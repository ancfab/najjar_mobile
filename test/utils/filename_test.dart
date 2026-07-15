import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/utils/filename.dart';

void main() {
  group('invoicePdfFilename', () {
    test('uses the exact lowercase "invoice-" prefix for #INV-8821', () {
      expect(invoicePdfFilename('#INV-8821'), 'invoice-INV-8821.pdf');
    });

    test('strips a leading # and keeps the hyphen', () {
      expect(invoicePdfFilename('#INV-8821'), 'invoice-INV-8821.pdf');
    });

    test('replaces spaces and slashes with hyphens', () {
      expect(invoicePdfFilename('INV 8821/A'), 'invoice-INV-8821-A.pdf');
    });

    test('collapses repeated unsafe characters into a single hyphen', () {
      expect(invoicePdfFilename('#--INV##8821--'), 'invoice-INV-8821.pdf');
    });

    test('falls back to a generic name for an all-unsafe input', () {
      expect(invoicePdfFilename('###'), 'invoice-invoice.pdf');
    });
  });
}
