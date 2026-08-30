// Unit checks for CreditUtilizationData: holds the raw availableCredit/
// usedCredit figures verbatim, and derives progress-bar ratios purely from
// those two values (no separate credit-limit field).

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/credit_utilization_data.dart';

void main() {
  test('holds the supplied availableCredit and usedCredit verbatim', () {
    const data = CreditUtilizationData(
      availableCredit: 57150.00,
      usedCredit: 42850.00,
    );

    expect(data.availableCredit, 57150.00);
    expect(data.usedCredit, 42850.00);
  });

  group('availableCreditRatio/usedCreditRatio', () {
    test(
      'are derived from availableCredit + usedCredit as the denominator',
      () {
        const data = CreditUtilizationData(
          availableCredit: 25000.00,
          usedCredit: 75000.00,
        );

        expect(data.availableCreditRatio, closeTo(0.25, 0.0001));
        expect(data.usedCreditRatio, closeTo(0.75, 0.0001));
      },
    );

    test(
      'both ratios are 0 when availableCredit and usedCredit are both 0',
      () {
        const data = CreditUtilizationData(availableCredit: 0, usedCredit: 0);

        expect(data.availableCreditRatio, 0.0);
        expect(data.usedCreditRatio, 0.0);
      },
    );

    test('usedCreditRatio is 1.0 when availableCredit is 0', () {
      const data = CreditUtilizationData(
        availableCredit: 0,
        usedCredit: 36711.73,
      );

      expect(data.availableCreditRatio, 0.0);
      expect(data.usedCreditRatio, 1.0);
    });
  });
}
