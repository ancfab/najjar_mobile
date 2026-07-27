// Unit tests for PaymentEntry.fromJson: exact camelCase key parsing (never
// LedgerEntry's PascalCase_With_Underscores keys), safe int-or-double
// amount parsing, strict date-only parsing, malformed/missing-field
// rejection with no silent fallback values, and toString() safety.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/payment_entry.dart';

Map<String, dynamic> _validJson({
  Object? amount = 100.50,
  Object? remaining = 0.0,
}) => {
  'entryNo': 1001,
  'postingDate': '2026-01-05',
  'documentNo': 'PAY-001',
  'customerNo': 'CLNT-0001',
  'customerName': 'Test Customer One',
  'currencyCode': 'USD',
  'amount': amount,
  'remainingAmount': remaining,
  'open': false,
  'dueDate': '2026-01-15',
};

void main() {
  group('PaymentEntry.fromJson', () {
    test('parses all exact camelCase keys', () {
      final entry = PaymentEntry.fromJson(_validJson());

      expect(entry.entryNo, 1001);
      expect(entry.postingDate, DateTime(2026, 1, 5));
      expect(entry.documentNo, 'PAY-001');
      expect(entry.customerNo, 'CLNT-0001');
      expect(entry.customerName, 'Test Customer One');
      expect(entry.currencyCode, 'USD');
      expect(entry.amount, 100.50);
      expect(entry.remainingAmount, 0.0);
      expect(entry.dueDate, DateTime(2026, 1, 15));
      expect(entry.isOpen, isFalse);
    });

    test('parses an integer amount/remainingAmount as double', () {
      final entry = PaymentEntry.fromJson(
        _validJson(amount: 100, remaining: 50),
      );

      expect(entry.amount, 100.0);
      expect(entry.amount, isA<double>());
      expect(entry.remainingAmount, 50.0);
      expect(entry.remainingAmount, isA<double>());
    });

    test('parses a decimal amount/remainingAmount', () {
      final entry = PaymentEntry.fromJson(
        _validJson(amount: 100.75, remaining: 25.25),
      );

      expect(entry.amount, 100.75);
      expect(entry.remainingAmount, 25.25);
    });

    test('parses open as a Boolean, true and false', () {
      final openJson = _validJson();
      openJson['open'] = true;
      expect(PaymentEntry.fromJson(openJson).isOpen, isTrue);

      final closedJson = _validJson();
      closedJson['open'] = false;
      expect(PaymentEntry.fromJson(closedJson).isOpen, isFalse);
    });

    test('parses ISO date-only values correctly', () {
      final entry = PaymentEntry.fromJson(_validJson());
      expect(entry.postingDate.year, 2026);
      expect(entry.postingDate.month, 1);
      expect(entry.postingDate.day, 5);
      expect(entry.dueDate.year, 2026);
      expect(entry.dueDate.month, 1);
      expect(entry.dueDate.day, 15);
    });

    test('rejects a missing entryNo', () {
      final json = _validJson()..remove('entryNo');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a non-int entryNo', () {
      final json = _validJson();
      json['entryNo'] = 'not-an-int';
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a missing postingDate', () {
      final json = _validJson()..remove('postingDate');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a malformed postingDate', () {
      final json = _validJson();
      json['postingDate'] = 'not-a-date';
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a postingDate with a time component', () {
      final json = _validJson();
      json['postingDate'] = '2026-01-05T00:00:00Z';
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a missing dueDate', () {
      final json = _validJson()..remove('dueDate');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a malformed dueDate', () {
      final json = _validJson();
      json['dueDate'] = 'not-a-date';
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a missing amount', () {
      final json = _validJson()..remove('amount');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a non-numeric amount', () {
      final json = _validJson();
      json['amount'] = 'not-a-number';
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a missing remainingAmount', () {
      final json = _validJson()..remove('remainingAmount');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a missing open flag', () {
      final json = _validJson()..remove('open');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a non-bool open flag', () {
      final json = _validJson();
      json['open'] = 'false';
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('accepts an empty documentNo/customerNo/customerName/currencyCode '
        '(the Payments contract requires a String type only, not non-empty '
        '— unlike LedgerEntry, which enforces non-empty as its own choice, '
        'not a documented contract rule)', () {
      for (final key in [
        'documentNo',
        'customerNo',
        'customerName',
        'currencyCode',
      ]) {
        final json = _validJson();
        json[key] = '';
        final entry = PaymentEntry.fromJson(json);
        expect(
          switch (key) {
            'documentNo' => entry.documentNo,
            'customerNo' => entry.customerNo,
            'customerName' => entry.customerName,
            'currencyCode' => entry.currencyCode,
            _ => throw StateError('unreachable'),
          },
          '',
          reason:
              'An empty "$key" must be passed through unmodified, '
              'never rejected or replaced.',
        );
      }
    });

    test(
      'rejects a non-string documentNo/customerNo/customerName/currencyCode',
      () {
        for (final key in [
          'documentNo',
          'customerNo',
          'customerName',
          'currencyCode',
        ]) {
          final json = _validJson();
          json[key] = 12345;
          expect(
            () => PaymentEntry.fromJson(json),
            throwsFormatException,
            reason: 'A non-string "$key" must still throw.',
          );
        }
      },
    );

    test('rejects a missing customerNo', () {
      final json = _validJson()..remove('customerNo');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects a missing currencyCode', () {
      final json = _validJson()..remove('currencyCode');
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects Ledger-style PascalCase_With_Underscores field names '
        '(does not accept Entry_No as an alias for entryNo)', () {
      final json = {
        'Entry_No': 1001,
        'Posting_Date': '2026-01-05',
        'Document_No': 'PAY-001',
        'Customer_No': 'CLNT-0001',
        'Customer_Name': 'Test Customer One',
        'Currency_Code': 'USD',
        'Amount': 100.50,
        'Remaining_Amount': 0.0,
        'Open': false,
        'Due_Date': '2026-01-15',
      };
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('rejects lower_snake_case field names (does not accept entry_no as '
        'an alias for entryNo)', () {
      final json = {
        'entry_no': 1001,
        'posting_date': '2026-01-05',
        'document_no': 'PAY-001',
        'customer_no': 'CLNT-0001',
        'customer_name': 'Test Customer One',
        'currency_code': 'USD',
        'amount': 100.50,
        'remaining_amount': 0.0,
        'open': false,
        'due_date': '2026-01-15',
      };
      expect(() => PaymentEntry.fromJson(json), throwsFormatException);
    });

    test('does not silently apply a fallback amount/currencyCode/postingDate/'
        'documentNo when the field is missing', () {
      for (final key in [
        'amount',
        'currencyCode',
        'postingDate',
        'documentNo',
      ]) {
        final json = _validJson()..remove(key);
        expect(
          () => PaymentEntry.fromJson(json),
          throwsFormatException,
          reason: 'Missing "$key" must throw, never fall back silently.',
        );
      }
    });

    test('does not expose sensitive data in toString', () {
      final entry = PaymentEntry.fromJson(_validJson());
      final text = entry.toString();

      expect(text, isNot(contains('Test Customer One')));
      expect(text, isNot(contains('100.5')));
      expect(text, contains('1001'));
      expect(text, contains('PAY-001'));
    });
  });
}
