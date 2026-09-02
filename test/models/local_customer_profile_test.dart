// Unit tests for LocalCustomerProfile: JSON round-trip and graceful
// handling of missing/wrong-typed fields (backward compatibility with a
// partially-written or future-format record).

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/local_customer_profile.dart';

void main() {
  group('LocalCustomerProfile', () {
    const profile = LocalCustomerProfile(
      fullName: 'Alexander Mitchell',
      email: 'alex.mitchell@example.com',
      company: 'Vanguard Global Logistics',
      businessAddress: '450 Fashion Ave, Suite 1205, New York, NY 10123',
    );

    test('round-trips through toJson/fromJson', () {
      final decoded = LocalCustomerProfile.fromJson(profile.toJson());

      expect(decoded, profile);
    });

    test('toJson uses the documented snake_case keys', () {
      expect(profile.toJson(), {
        'full_name': 'Alexander Mitchell',
        'email': 'alex.mitchell@example.com',
        'company': 'Vanguard Global Logistics',
        'business_address': '450 Fashion Ave, Suite 1205, New York, NY 10123',
      });
    });

    test(
      'a missing field resolves to an empty string rather than throwing',
      () {
        final decoded = LocalCustomerProfile.fromJson(const {
          'full_name': 'Alexander Mitchell',
        });

        expect(decoded.fullName, 'Alexander Mitchell');
        expect(decoded.email, '');
        expect(decoded.company, '');
        expect(decoded.businessAddress, '');
      },
    );

    test(
      'a wrong-typed field resolves to an empty string rather than throwing',
      () {
        final decoded = LocalCustomerProfile.fromJson(const {
          'full_name': 12345,
          'email': null,
          'company': ['not', 'a', 'string'],
          'business_address': 'Real address',
        });

        expect(decoded.fullName, '');
        expect(decoded.email, '');
        expect(decoded.company, '');
        expect(decoded.businessAddress, 'Real address');
      },
    );

    test('an empty JSON object resolves to all-empty fields', () {
      final decoded = LocalCustomerProfile.fromJson(const {});

      expect(decoded.fullName, '');
      expect(decoded.email, '');
      expect(decoded.company, '');
      expect(decoded.businessAddress, '');
    });

    test('equality and hashCode are value-based', () {
      const other = LocalCustomerProfile(
        fullName: 'Alexander Mitchell',
        email: 'alex.mitchell@example.com',
        company: 'Vanguard Global Logistics',
        businessAddress: '450 Fashion Ave, Suite 1205, New York, NY 10123',
      );

      expect(profile, other);
      expect(profile.hashCode, other.hashCode);
    });
  });
}
