// Unit tests for CustomerDetails.fromJson: strict parsing against the
// CONFIRMED LIVE backend response shape (lowercase "customerbalance"),
// defensive handling of the optional fields (absent vs. present-but-
// malformed), the dateFilter leniency, the data-wrapper vs. flat-shape
// envelope tolerance, and the legacy camelCase "customerBalance"
// compatibility fallback.
//
// The live response was captured via runtime diagnostics against the real
// ANC API on 2026-08-30 and looks like:
//
// {
//   "data": {
//     ...,
//     "customerbalance": 36711.73,
//     "overdueInvoicesAmount": 3844.085,
//     "lastPaymentAmount": 0,
//     "lastPaymentDate": "2025-03-18",
//     "availableCredit": 0,
//     "usedCredit": 36711.73,
//     "activeOrders": 0,
//     "DateFilter": ""
//   }
// }

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/customer_details.dart';

/// The confirmed live response shape, wrapped in the `data` object exactly
/// as the real backend returns it — lowercase `customerbalance`.
Map<String, dynamic> _liveResponseJson({String dateFilter = ''}) => {
  'data': {
    '@odata.etag': 'W/"JzE5OzUxMTYwNDMwOTM2NDM0Mzg4MjUxOzAwOyc="',
    'id': '98ce2d3d-86c9-ee11-9078-6045bd154cae',
    'customerCode': 'CLNT-0001',
    'customerName': 'ANC NAJJAR FURNITURE LLC SHJ BR',
    'customerbalance': 36711.73,
    'overdueInvoicesAmount': 3844.085,
    'lastPaymentAmount': 0,
    'lastPaymentDate': '2025-03-18',
    'availableCredit': 0,
    'usedCredit': 36711.73,
    'activeOrders': 0,
    'DateFilter': dateFilter,
  },
};

Map<String, dynamic> _validJson() => {
  'customerBalance': 36711.73,
  'availableCredit': 57150.00,
  'usedCredit': 42850.00,
};

void main() {
  group('the confirmed live response shape', () {
    test('parses every field from the real backend payload', () {
      final details = CustomerDetails.fromJson(_liveResponseJson());

      expect(details.customerBalance, 36711.73);
      expect(details.availableCredit, 0);
      expect(details.usedCredit, 36711.73);
      expect(details.overdueInvoicesAmount, 3844.085);
      expect(details.lastPaymentAmount, 0);
      expect(details.lastPaymentDate, DateTime(2025, 3, 18));
      expect(details.activeOrders, 0);
      expect(details.dateFilter, '');
    });

    test(
      'parses the date-filtered response, DateFilter="07/31/26..08/30/26"',
      () {
        final details = CustomerDetails.fromJson(
          _liveResponseJson(dateFilter: '07/31/26..08/30/26'),
        );

        expect(details.customerBalance, 36711.73);
        expect(details.dateFilter, '07/31/26..08/30/26');
      },
    );
  });

  group('customerBalance key resolution', () {
    test('reads the canonical live key "customerbalance" (lowercase)', () {
      final details = CustomerDetails.fromJson({
        'customerbalance': 36711.73,
        'availableCredit': 0,
        'usedCredit': 36711.73,
      });

      expect(details.customerBalance, 36711.73);
    });

    test('falls back to legacy camelCase "customerBalance" when the lowercase '
        'key is entirely absent (compatibility only, never preferred)', () {
      final details = CustomerDetails.fromJson(_validJson());

      expect(details.customerBalance, 36711.73);
    });

    test('prefers the canonical lowercase key when both are present', () {
      final json = _validJson();
      json['customerbalance'] = 99999.99;

      final details = CustomerDetails.fromJson(json);

      expect(details.customerBalance, 99999.99);
    });

    test('throws FormatException when neither "customerbalance" nor '
        '"customerBalance" is present', () {
      final json = _validJson()..remove('customerBalance');

      expect(() => CustomerDetails.fromJson(json), throwsFormatException);
    });

    test('throws FormatException when the resolved key is present but the '
        'wrong type — never silently defaults to zero', () {
      final json = {
        'customerbalance': 'not a number',
        'availableCredit': 0,
        'usedCredit': 36711.73,
      };

      expect(() => CustomerDetails.fromJson(json), throwsFormatException);
    });
  });

  group('other required fields', () {
    test('throws FormatException when availableCredit is the wrong type', () {
      final json = _validJson();
      json['availableCredit'] = 'not a number';

      expect(() => CustomerDetails.fromJson(json), throwsFormatException);
    });

    test('throws FormatException when usedCredit is missing', () {
      final json = _validJson()..remove('usedCredit');

      expect(() => CustomerDetails.fromJson(json), throwsFormatException);
    });

    test('accepts an integer JSON value for a monetary field', () {
      final json = _validJson();
      json['usedCredit'] = 42850;

      final details = CustomerDetails.fromJson(json);

      expect(details.usedCredit, 42850.0);
    });
  });

  group('optional numeric fields', () {
    test('are null when absent', () {
      final details = CustomerDetails.fromJson(_validJson());

      expect(details.overdueInvoicesAmount, isNull);
      expect(details.lastPaymentAmount, isNull);
      expect(details.activeOrders, isNull);
    });

    test('parse when present', () {
      final json = _validJson();
      json['overdueInvoicesAmount'] = 1200.5;
      json['lastPaymentAmount'] = 500;
      json['activeOrders'] = 3;

      final details = CustomerDetails.fromJson(json);

      expect(details.overdueInvoicesAmount, 1200.5);
      expect(details.lastPaymentAmount, 500.0);
      expect(details.activeOrders, 3);
    });

    test('a present-but-malformed overdueInvoicesAmount throws rather than '
        'being silently replaced with a fake value', () {
      final json = _validJson();
      json['overdueInvoicesAmount'] = 'not a number';

      expect(() => CustomerDetails.fromJson(json), throwsFormatException);
    });
  });

  group('lastPaymentDate', () {
    test('is null when absent', () {
      final details = CustomerDetails.fromJson(_validJson());
      expect(details.lastPaymentDate, isNull);
    });

    test('parses a yyyy-MM-dd date-only string', () {
      final json = _validJson();
      json['lastPaymentDate'] = '2026-01-05';

      final details = CustomerDetails.fromJson(json);

      expect(details.lastPaymentDate, DateTime(2026, 1, 5));
    });

    test('throws FormatException for a malformed date string', () {
      final json = _validJson();
      json['lastPaymentDate'] = 'not-a-date';

      expect(() => CustomerDetails.fromJson(json), throwsFormatException);
    });
  });

  group('dateFilter', () {
    test('is null when absent', () {
      final details = CustomerDetails.fromJson(_validJson());
      expect(details.dateFilter, isNull);
    });

    test('parses an empty-string value as "" (not null)', () {
      final json = _validJson();
      json['DateFilter'] = '';

      final details = CustomerDetails.fromJson(json);

      expect(details.dateFilter, '');
    });

    test('parses a non-empty String value', () {
      final json = _validJson();
      json['DateFilter'] = 'Last 30 days';

      final details = CustomerDetails.fromJson(json);

      expect(details.dateFilter, 'Last 30 days');
    });

    test('treats a present non-String value as absent rather than throwing '
        '(shape not confirmed by the contract)', () {
      final json = _validJson();
      json['DateFilter'] = {'from': '2026-01-01', 'to': '2026-01-30'};

      final details = CustomerDetails.fromJson(json);

      expect(details.dateFilter, isNull);
    });
  });

  group('envelope shape', () {
    test('parses a flat top-level shape', () {
      final details = CustomerDetails.fromJson(_validJson());
      expect(details.customerBalance, 36711.73);
    });

    test('parses fields nested under a top-level "data" object', () {
      final wrapped = {'data': _validJson()};

      final details = CustomerDetails.fromJson(wrapped);

      expect(details.customerBalance, 36711.73);
      expect(details.availableCredit, 57150.00);
      expect(details.usedCredit, 42850.00);
    });
  });
}
