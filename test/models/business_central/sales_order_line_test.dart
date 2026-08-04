// Unit tests for BusinessCentralSalesOrderLine.fromJson: exact
// PascalCase_With_Underscores key parsing (including the literal "No." key),
// safe int-or-double numeric parsing, malformed-field rejection, the
// Document_No+Line_No identity, and toString() safety.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/sales_order_line.dart';

Map<String, dynamic> _validJson({
  Object? quantity = 12,
  Object? unitPrice = 15,
  Object? amount = 180,
}) => {
  'Document_No': 'SO-24001',
  'Line_No': 10000,
  'Sell_to_Customer_No': 'CLNT-0001',
  'Sell_to_Customer_Name': 'Test Customer One',
  'No.': '880107',
  'Description': 'Test Fabric Item',
  'Quantity': quantity,
  'Unit_Price': unitPrice,
  'Amount': amount,
};

void main() {
  group('BusinessCentralSalesOrderLine.fromJson', () {
    test('parses all exact PascalCase_With_Underscores keys, including the '
        'literal "No." key', () {
      final line = BusinessCentralSalesOrderLine.fromJson(_validJson());

      expect(line.documentNo, 'SO-24001');
      expect(line.lineNo, 10000);
      expect(line.sellToCustomerNo, 'CLNT-0001');
      expect(line.sellToCustomerName, 'Test Customer One');
      expect(line.itemNo, '880107');
      expect(line.description, 'Test Fabric Item');
      expect(line.quantity, 12.0);
      expect(line.unitPrice, 15.0);
      expect(line.amount, 180.0);
    });

    test('parses an integer Quantity/Unit_Price/Amount as double', () {
      final line = BusinessCentralSalesOrderLine.fromJson(_validJson());

      expect(line.quantity, isA<double>());
      expect(line.unitPrice, isA<double>());
      expect(line.amount, isA<double>());
    });

    test('parses a decimal Quantity/Unit_Price/Amount', () {
      final line = BusinessCentralSalesOrderLine.fromJson(
        _validJson(quantity: 12.5, unitPrice: 15.25, amount: 190.625),
      );

      expect(line.quantity, 12.5);
      expect(line.unitPrice, 15.25);
      expect(line.amount, 190.625);
    });

    test('rejects a missing Document_No', () {
      final json = _validJson()..remove('Document_No');
      expect(
        () => BusinessCentralSalesOrderLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects an empty Document_No', () {
      final json = _validJson();
      json['Document_No'] = '';
      expect(
        () => BusinessCentralSalesOrderLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a missing Line_No', () {
      final json = _validJson()..remove('Line_No');
      expect(
        () => BusinessCentralSalesOrderLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-int Line_No', () {
      final json = _validJson();
      json['Line_No'] = 'not-an-int';
      expect(
        () => BusinessCentralSalesOrderLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a missing "No." (item number)', () {
      final json = _validJson()..remove('No.');
      expect(
        () => BusinessCentralSalesOrderLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('does not accept a normalized "No" key in place of "No."', () {
      final json = _validJson()..remove('No.');
      json['No'] = '880107';
      expect(
        () => BusinessCentralSalesOrderLine.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-numeric Amount', () {
      final json = _validJson();
      json['Amount'] = 'not-a-number';
      expect(
        () => BusinessCentralSalesOrderLine.fromJson(json),
        throwsFormatException,
      );
    });

    group('identity', () {
      test('combines Document_No and Line_No', () {
        final line = BusinessCentralSalesOrderLine.fromJson(_validJson());
        expect(line.identity, contains('SO-24001'));
        expect(line.identity, contains('10000'));
      });

      test('two rows sharing Document_No but differing in Line_No have '
          'distinct identities', () {
        final first = BusinessCentralSalesOrderLine.fromJson(_validJson());
        final json = _validJson();
        json['Line_No'] = 20000;
        final second = BusinessCentralSalesOrderLine.fromJson(json);

        expect(first.identity, isNot(second.identity));
      });

      test('Document_No alone is never used as identity (two different '
          'documents with the same Line_No differ)', () {
        final first = BusinessCentralSalesOrderLine.fromJson(_validJson());
        final json = _validJson();
        json['Document_No'] = 'SO-24002';
        final second = BusinessCentralSalesOrderLine.fromJson(json);

        expect(first.identity, isNot(second.identity));
      });
    });

    test('does not expose sensitive data in toString', () {
      final line = BusinessCentralSalesOrderLine.fromJson(_validJson());
      final text = line.toString();

      expect(text, isNot(contains('Test Customer One')));
      expect(text, isNot(contains('180')));
      expect(text, contains('SO-24001'));
      expect(text, contains('10000'));
    });
  });
}
