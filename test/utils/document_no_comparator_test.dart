// Unit tests for compareDocumentNoNatural: the natural-sort comparator used
// to pick the "higher" invoice Document_No per the confirmed contract (see
// invoice_grouping.dart), never Posting_Date.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/utils/document_no_comparator.dart';

void main() {
  group('compareDocumentNoNatural', () {
    test('numeric suffix compares by magnitude, not lexicographically', () {
      expect(compareDocumentNoNatural('SO-24001', 'SO-24010'), lessThan(0));
      expect(compareDocumentNoNatural('SO-24010', 'SO-24001'), greaterThan(0));
    });

    test('single- vs double-digit suffix: "-9" sorts before "-10"', () {
      expect(compareDocumentNoNatural('INV-9', 'INV-10'), lessThan(0));
      expect(compareDocumentNoNatural('INV-10', 'INV-9'), greaterThan(0));
    });

    test('identical values compare equal', () {
      expect(compareDocumentNoNatural('SO-24001', 'SO-24001'), 0);
    });

    test('purely numeric strings compare by magnitude', () {
      expect(compareDocumentNoNatural('24001', '24010'), lessThan(0));
    });

    test('different alphabetic prefixes compare as plain strings', () {
      expect(compareDocumentNoNatural('A-1', 'B-1'), lessThan(0));
    });

    test('leading zeros within an otherwise-identical numeric run compare '
        'equal (same numeric magnitude)', () {
      expect(compareDocumentNoNatural('INV-007', 'INV-7'), 0);
    });

    test('a real-world representative set sorts to the confirmed highest '
        'last', () {
      final values = ['INV-24003', 'INV-24010', 'INV-9', 'INV-24001']
        ..sort(compareDocumentNoNatural);
      expect(values.last, 'INV-24010');
    });
  });
}
