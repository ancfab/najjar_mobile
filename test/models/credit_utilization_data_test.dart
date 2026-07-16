// Unit checks for CreditUtilizationData's ratio getters: the progress-bar
// fractions must be calculated from the supplied totalCredit/available/used
// values rather than being hardcoded, and must stay within 0..1.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/credit_utilization_data.dart';

void main() {
  group('availableCreditRatio and usedCreditRatio', () {
    test('are calculated as a fraction of totalCredit', () {
      const data = CreditUtilizationData(
        totalCredit: 100000.00,
        availableCredit: 57150.00,
        usedCredit: 42850.00,
      );

      expect(data.availableCreditRatio, closeTo(0.5715, 0.0001));
      expect(data.usedCreditRatio, closeTo(0.4285, 0.0001));
    });

    test('change when the underlying figures change', () {
      const data = CreditUtilizationData(
        totalCredit: 50000.00,
        availableCredit: 10000.00,
        usedCredit: 40000.00,
      );

      expect(data.availableCreditRatio, closeTo(0.2, 0.0001));
      expect(data.usedCreditRatio, closeTo(0.8, 0.0001));
    });

    test('clamp to 1.0 when a figure exceeds totalCredit', () {
      const data = CreditUtilizationData(
        totalCredit: 10000.00,
        availableCredit: 12000.00,
        usedCredit: 0,
      );

      expect(data.availableCreditRatio, 1.0);
    });

    test('are 0 when totalCredit is 0', () {
      const data = CreditUtilizationData(
        totalCredit: 0,
        availableCredit: 500,
        usedCredit: 500,
      );

      expect(data.availableCreditRatio, 0.0);
      expect(data.usedCreditRatio, 0.0);
    });
  });
}
