// Unit tests for LedgerEntry.fromJson: exact PascalCase_With_Underscores
// key parsing, safe int-or-double amount parsing, strict date-only
// parsing, malformed-field rejection, and toString() safety.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/ledger_entry.dart';

Map<String, dynamic> _validJson({
  Object? amount = 100.50,
  Object? remaining = 100.50,
}) => {
  'Entry_No': 1001,
  'Posting_Date': '2026-01-05',
  'Document_Type': 'Invoice',
  'Document_No': 'INV-TEST-001',
  'Customer_No': 'CLNT-0001',
  'Customer_Name': 'Test Customer One',
  'Currency_Code': 'USD',
  'Amount': amount,
  'Remaining_Amount': remaining,
  'Due_Date': '2026-01-15',
  'Open': true,
};

void main() {
  group('LedgerEntry.fromJson', () {
    test('parses all exact PascalCase_With_Underscores keys', () {
      final entry = LedgerEntry.fromJson(_validJson());

      expect(entry.entryNo, 1001);
      expect(entry.postingDate, DateTime(2026, 1, 5));
      expect(entry.documentType, 'Invoice');
      expect(entry.documentNo, 'INV-TEST-001');
      expect(entry.customerNo, 'CLNT-0001');
      expect(entry.customerName, 'Test Customer One');
      expect(entry.currencyCode, 'USD');
      expect(entry.amount, 100.50);
      expect(entry.remainingAmount, 100.50);
      expect(entry.dueDate, DateTime(2026, 1, 15));
      expect(entry.isOpen, isTrue);
    });

    test('parses an integer Amount/Remaining_Amount as double', () {
      final entry = LedgerEntry.fromJson(
        _validJson(amount: 100, remaining: 50),
      );

      expect(entry.amount, 100.0);
      expect(entry.amount, isA<double>());
      expect(entry.remainingAmount, 50.0);
    });

    test('parses a decimal Amount/Remaining_Amount', () {
      final entry = LedgerEntry.fromJson(
        _validJson(amount: 100.75, remaining: 25.25),
      );

      expect(entry.amount, 100.75);
      expect(entry.remainingAmount, 25.25);
    });

    test('parses ISO date-only values correctly', () {
      final entry = LedgerEntry.fromJson(_validJson());
      expect(entry.postingDate.year, 2026);
      expect(entry.postingDate.month, 1);
      expect(entry.postingDate.day, 5);
    });

    test('rejects a missing Entry_No', () {
      final json = _validJson()..remove('Entry_No');
      expect(() => LedgerEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a non-int Entry_No', () {
      final json = _validJson();
      json['Entry_No'] = 'not-an-int';
      expect(() => LedgerEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a malformed Posting_Date', () {
      final json = _validJson();
      json['Posting_Date'] = 'not-a-date';
      expect(() => LedgerEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a Posting_Date with a time component', () {
      final json = _validJson();
      json['Posting_Date'] = '2026-01-05T00:00:00Z';
      expect(() => LedgerEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a non-numeric Amount', () {
      final json = _validJson();
      json['Amount'] = 'not-a-number';
      expect(() => LedgerEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a missing Open flag', () {
      final json = _validJson()..remove('Open');
      expect(() => LedgerEntry.fromJson(json), throwsFormatException);
    });

    test('rejects an empty Document_No', () {
      final json = _validJson();
      json['Document_No'] = '';
      expect(() => LedgerEntry.fromJson(json), throwsFormatException);
    });

    test('does not expose sensitive data in toString', () {
      final entry = LedgerEntry.fromJson(_validJson());
      final text = entry.toString();

      expect(text, isNot(contains('Test Customer One')));
      expect(text, isNot(contains('100.5')));
      expect(text, contains('1001'));
    });
  });
}
