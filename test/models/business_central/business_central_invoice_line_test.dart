// Unit tests for BusinessCentralInvoiceLine.fromJson: exact
// PascalCase_With_Underscores key parsing (never PaymentEntry's camelCase
// keys), the confirmed-live Posting_Date nullability mismatch, safe
// int-or-double numeric parsing, ignoring undocumented/extra fields
// (especially Unit_Cost_LCY), malformed/missing-field rejection with no
// silent fallback values, and toString() redaction.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/business_central_invoice_line.dart';

Map<String, dynamic> _validJson({
  Object? postingDate = '2026-01-05',
  Object? quantity = 12,
  Object? unitPrice = 850.0,
  Object? amount = 10200.0,
  Object? amountIncludingVat = 10710.0,
  Object? currencyCode = 'AED',
}) => {
  'Document_No': 'INV-1001',
  'Line_No': 10000,
  'Posting_Date': postingDate,
  'Sell_to_Customer_No': 'CLNT-0001',
  'Sell_to_Customer_Name': 'Test Customer One',
  'Type': 'Item',
  'No': 'ITEM-001',
  'Description': 'Egyptian Cotton Sateen (600TC)',
  'Quantity': quantity,
  'Unit_Price': unitPrice,
  'Amount': amount,
  'Amount_Including_VAT': amountIncludingVat,
  'Order_No': 'ORD-8829',
  'Currency_Code': currencyCode,
};

/// Every undocumented field observed on the confirmed live deployed
/// response, including the internal-cost field `Unit_Cost_LCY` — this class
/// must ignore all of these, never model or expose them.
Map<String, dynamic> _withExtraLiveFields(Map<String, dynamic> json) => {
  ...json,
  '@odata.etag': 'W/"JzQ0O1234567890abcdef;1234567\'"',
  'Variant_Code': '',
  'Description_2': '',
  'Shortcut_Dimension_1_Code': '',
  'Shortcut_Dimension_2_Code': '',
  'Unit_of_Measure_Code': 'ROLL',
  'Unit_of_Measure': 'Rolls',
  'Unit_Cost_LCY': 612.5,
  'Line_Discount_Percent': 0,
  'Line_Discount_Amount': 0,
  'Allow_Invoice_Disc': true,
  'Inv_Discount_Amount': 0,
  'Appl_to_Item_Entry': 0,
  'Job_No': '',
};

void main() {
  group('BusinessCentralInvoiceLine.fromJson', () {
    test('parses all approved exact PascalCase_With_Underscores keys', () {
      final line = BusinessCentralInvoiceLine.fromJson(_validJson());

      expect(line.documentNo, 'INV-1001');
      expect(line.lineNo, 10000);
      expect(line.postingDate, DateTime(2026, 1, 5));
      expect(line.sellToCustomerNo, 'CLNT-0001');
      expect(line.sellToCustomerName, 'Test Customer One');
      expect(line.type, 'Item');
      expect(line.itemNo, 'ITEM-001');
      expect(line.description, 'Egyptian Cotton Sateen (600TC)');
      expect(line.quantity, 12.0);
      expect(line.unitPrice, 850.0);
      expect(line.amount, 10200.0);
      expect(line.amountIncludingVat, 10710.0);
      expect(line.orderNo, 'ORD-8829');
      expect(line.currencyCode, 'AED');
    });

    test('ignores every undocumented extra field observed on the live '
        'response, including Unit_Cost_LCY', () {
      final json = _withExtraLiveFields(_validJson());

      final line = BusinessCentralInvoiceLine.fromJson(json);

      expect(line.documentNo, 'INV-1001');
      expect(line.lineNo, 10000);
      // Confirm there is no field/getter surfacing Unit_Cost_LCY at all —
      // toString() is the only inspectable surface, and it must not expose
      // it either.
      expect(line.toString(), isNot(contains('612.5')));
      expect(line.toString(), isNot(contains('Unit_Cost')));
    });

    group('Posting_Date (confirmed live contract mismatch)', () {
      test('a missing Posting_Date key parses as null', () {
        final json = _validJson()..remove('Posting_Date');
        final line = BusinessCentralInvoiceLine.fromJson(json);
        expect(line.postingDate, isNull);
      });

      test('an explicit null Posting_Date parses as null', () {
        final line = BusinessCentralInvoiceLine.fromJson(
          _validJson(postingDate: null),
        );
        expect(line.postingDate, isNull);
      });

      test('a valid yyyy-MM-dd Posting_Date parses correctly', () {
        final line = BusinessCentralInvoiceLine.fromJson(
          _validJson(postingDate: '2026-03-21'),
        );
        expect(line.postingDate, DateTime(2026, 3, 21));
      });

      test('a present but malformed Posting_Date string throws', () {
        expect(
          () => BusinessCentralInvoiceLine.fromJson(
            _validJson(postingDate: 'not-a-date'),
          ),
          throwsFormatException,
        );
      });

      test('a present Posting_Date with a time component throws', () {
        expect(
          () => BusinessCentralInvoiceLine.fromJson(
            _validJson(postingDate: '2026-01-05T00:00:00Z'),
          ),
          throwsFormatException,
        );
      });

      test('a present non-String Posting_Date throws, never treated as '
          'unknown/null', () {
        expect(
          () => BusinessCentralInvoiceLine.fromJson(
            _validJson(postingDate: 20260105),
          ),
          throwsFormatException,
        );
      });

      test('never substitutes DateTime.now() or any other fallback date '
          'when Posting_Date is missing', () {
        final json = _validJson()..remove('Posting_Date');
        final line = BusinessCentralInvoiceLine.fromJson(json);
        expect(line.postingDate, isNull);
        expect(line.postingDate, isNot(DateTime.now()));
      });
    });

    group('Amount_Including_VAT (confirmed live contract mismatch)', () {
      test('a missing Amount_Including_VAT key parses as null', () {
        final json = _validJson()..remove('Amount_Including_VAT');
        final line = BusinessCentralInvoiceLine.fromJson(json);
        expect(line.amountIncludingVat, isNull);
      });

      test('an explicit null Amount_Including_VAT parses as null', () {
        final line = BusinessCentralInvoiceLine.fromJson(
          _validJson(amountIncludingVat: null),
        );
        expect(line.amountIncludingVat, isNull);
      });

      test('a valid int or double Amount_Including_VAT parses correctly', () {
        expect(
          BusinessCentralInvoiceLine.fromJson(
            _validJson(amountIncludingVat: 10710),
          ).amountIncludingVat,
          10710.0,
        );
        expect(
          BusinessCentralInvoiceLine.fromJson(
            _validJson(amountIncludingVat: 10710.5),
          ).amountIncludingVat,
          10710.5,
        );
      });

      test('a present non-numeric Amount_Including_VAT throws, never '
          'treated as unknown/null', () {
        expect(
          () => BusinessCentralInvoiceLine.fromJson(
            _validJson(amountIncludingVat: 'not-a-number'),
          ),
          throwsFormatException,
        );
      });

      test('never substitutes Amount or 0 when Amount_Including_VAT is '
          'missing', () {
        final json = _validJson(amount: 10200.0)
          ..remove('Amount_Including_VAT');
        final line = BusinessCentralInvoiceLine.fromJson(json);
        expect(line.amountIncludingVat, isNull);
        expect(line.amountIncludingVat, isNot(line.amount));
        expect(line.amountIncludingVat, isNot(0));
      });
    });

    group('Currency_Code (confirmed live "blankable" field, 2026-09-03)', () {
      test('a missing Currency_Code key parses as "" (never null)', () {
        final json = _validJson()..remove('Currency_Code');
        final line = BusinessCentralInvoiceLine.fromJson(json);
        expect(line.currencyCode, '');
      });

      test('an explicit null Currency_Code parses as "" (never null)', () {
        final line = BusinessCentralInvoiceLine.fromJson(
          _validJson(currencyCode: null),
        );
        expect(line.currencyCode, '');
      });

      test('an explicit "" Currency_Code (confirmed live on Lebanon\'s '
          'tenant) parses as "", not an error', () {
        final line = BusinessCentralInvoiceLine.fromJson(
          _validJson(currencyCode: ''),
        );
        expect(line.currencyCode, '');
      });

      test('a real currency code parses exactly as given', () {
        for (final code in ['USD', 'OMR', 'AED', 'IQD', 'SYP']) {
          expect(
            BusinessCentralInvoiceLine.fromJson(
              _validJson(currencyCode: code),
            ).currencyCode,
            code,
          );
        }
      });

      test('a present non-String Currency_Code throws, never treated as '
          'blank', () {
        expect(
          () => BusinessCentralInvoiceLine.fromJson(
            _validJson(currencyCode: 123),
          ),
          throwsFormatException,
        );
      });
    });

    group('Line_No', () {
      test('requires an int', () {
        final json = _validJson();
        json['Line_No'] = '10000';
        expect(
          () => BusinessCentralInvoiceLine.fromJson(json),
          throwsFormatException,
        );
      });

      test('rejects a missing Line_No', () {
        final json = _validJson()..remove('Line_No');
        expect(
          () => BusinessCentralInvoiceLine.fromJson(json),
          throwsFormatException,
        );
      });
    });

    group(
      'Quantity/Unit_Price/Amount/Amount_Including_VAT numeric parsing',
      () {
        test('Quantity accepts an int and converts to double', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(quantity: 5),
          );
          expect(line.quantity, 5.0);
          expect(line.quantity, isA<double>());
        });

        test('Quantity accepts a decimal', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(quantity: 5.5),
          );
          expect(line.quantity, 5.5);
        });

        test('Unit_Price accepts an int and converts to double', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(unitPrice: 410),
          );
          expect(line.unitPrice, 410.0);
          expect(line.unitPrice, isA<double>());
        });

        test('Unit_Price accepts a decimal', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(unitPrice: 410.25),
          );
          expect(line.unitPrice, 410.25);
        });

        test('Amount accepts an int and converts to double', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(amount: 2050),
          );
          expect(line.amount, 2050.0);
          expect(line.amount, isA<double>());
        });

        test('Amount accepts a decimal', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(amount: 2050.75),
          );
          expect(line.amount, 2050.75);
        });

        test('Amount_Including_VAT accepts an int and converts to double', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(amountIncludingVat: 2153),
          );
          expect(line.amountIncludingVat, 2153.0);
          expect(line.amountIncludingVat, isA<double>());
        });

        test('Amount_Including_VAT accepts a decimal', () {
          final line = BusinessCentralInvoiceLine.fromJson(
            _validJson(amountIncludingVat: 2153.25),
          );
          expect(line.amountIncludingVat, 2153.25);
        });

        test('rejects a non-numeric Quantity/Unit_Price/Amount/'
            'Amount_Including_VAT', () {
          for (final key in [
            'Quantity',
            'Unit_Price',
            'Amount',
            'Amount_Including_VAT',
          ]) {
            final json = _validJson();
            json[key] = 'not-a-number';
            expect(
              () => BusinessCentralInvoiceLine.fromJson(json),
              throwsFormatException,
              reason: 'A non-numeric "$key" must still throw.',
            );
          }
        });
      },
    );

    group('required-key presence and type', () {
      test('rejects each missing required key', () {
        for (final key in [
          'Document_No',
          'Line_No',
          'Sell_to_Customer_No',
          'Sell_to_Customer_Name',
          'Type',
          'No',
          'Description',
          'Quantity',
          'Unit_Price',
          'Amount',
          // Posting_Date/Amount_Including_VAT are deliberately excluded —
          // both are optional, covered by their own dedicated groups above.
          'Order_No',
        ]) {
          final json = _validJson()..remove(key);
          expect(
            () => BusinessCentralInvoiceLine.fromJson(json),
            throwsFormatException,
            reason: 'Missing "$key" must throw, never fall back silently.',
          );
        }
      });

      test('rejects wrong types for each String field', () {
        for (final key in [
          'Document_No',
          'Sell_to_Customer_No',
          'Sell_to_Customer_Name',
          'Type',
          'No',
          'Description',
          'Order_No',
        ]) {
          final json = _validJson();
          json[key] = 12345;
          expect(
            () => BusinessCentralInvoiceLine.fromJson(json),
            throwsFormatException,
            reason: 'A non-string "$key" must still throw.',
          );
        }
      });

      test('empty String fields (Document_No, Sell_to_Customer_No, '
          'Sell_to_Customer_Name, Type, No, Description, Order_No) pass '
          'through unchanged', () {
        for (final key in [
          'Document_No',
          'Sell_to_Customer_No',
          'Sell_to_Customer_Name',
          'Type',
          'No',
          'Description',
          'Order_No',
        ]) {
          final json = _validJson();
          json[key] = '';
          final line = BusinessCentralInvoiceLine.fromJson(json);
          final actual = switch (key) {
            'Document_No' => line.documentNo,
            'Sell_to_Customer_No' => line.sellToCustomerNo,
            'Sell_to_Customer_Name' => line.sellToCustomerName,
            'Type' => line.type,
            'No' => line.itemNo,
            'Description' => line.description,
            'Order_No' => line.orderNo,
            _ => throw StateError('unreachable'),
          };
          expect(
            actual,
            '',
            reason:
                'An empty "$key" must be passed through unmodified, '
                'never rejected or replaced.',
          );
        }
      });
    });

    test('rejects Payments-style camelCase field names (does not accept '
        'documentNo as an alias for Document_No)', () {
      final json = {
        'documentNo': 'INV-1001',
        'lineNo': 10000,
        'postingDate': '2026-01-05',
        'sellToCustomerNo': 'CLNT-0001',
        'sellToCustomerName': 'Test Customer One',
        'type': 'Item',
        'itemNo': 'ITEM-001',
        'description': 'Egyptian Cotton Sateen (600TC)',
        'quantity': 12,
        'unitPrice': 850.0,
        'amount': 10200.0,
        'amountIncludingVat': 10710.0,
        'orderNo': 'ORD-8829',
      };
      expect(
        () => BusinessCentralInvoiceLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects lower_snake_case field names (does not accept '
        'document_no as an alias for Document_No)', () {
      final json = {
        'document_no': 'INV-1001',
        'line_no': 10000,
        'posting_date': '2026-01-05',
        'sell_to_customer_no': 'CLNT-0001',
        'sell_to_customer_name': 'Test Customer One',
        'type': 'Item',
        'no': 'ITEM-001',
        'description': 'Egyptian Cotton Sateen (600TC)',
        'quantity': 12,
        'unit_price': 850.0,
        'amount': 10200.0,
        'amount_including_vat': 10710.0,
        'order_no': 'ORD-8829',
      };
      expect(
        () => BusinessCentralInvoiceLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('does not silently apply a fallback value for any required field '
        'when missing', () {
      for (final key in [
        'Document_No',
        'Sell_to_Customer_No',
        'Sell_to_Customer_Name',
        'Amount',
      ]) {
        final json = _validJson()..remove(key);
        expect(
          () => BusinessCentralInvoiceLine.fromJson(json),
          throwsFormatException,
          reason: 'Missing "$key" must throw, never fall back silently.',
        );
      }
    });

    test('does not expose sensitive data in toString', () {
      final line = BusinessCentralInvoiceLine.fromJson(_validJson());
      final text = line.toString();

      expect(text, isNot(contains('Test Customer One')));
      expect(text, isNot(contains('CLNT-0001')));
      expect(text, isNot(contains('10200')));
      expect(text, isNot(contains('10710')));
      expect(text, isNot(contains('850')));
      expect(text, contains('INV-1001'));
      expect(text, contains('10000'));
    });
  });
}
