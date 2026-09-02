// Unit tests for buildAccountStatementPdfBytes: verifies it produces a
// real, non-empty PDF document containing the required Account Statement
// text and figures, without depending on any platform plugin.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/account_statement_data.dart';
import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/models/credit_utilization_data.dart';
import 'package:anc_fabrics/services/account_statement_exporter.dart';

void main() {
  final data = AccountStatementData(
    customerBalance: 36711.73,
    creditUtilization: const CreditUtilizationData(
      availableCredit: 57150.00,
      usedCredit: 42850.00,
    ),
    historyFrom: DateTime.utc(2023, 10, 1),
    historyTo: DateTime.utc(2023, 10, 30),
    generatedAt: DateTime.utc(2023, 10, 30),
  );

  group('buildAccountStatementPdfBytes', () {
    test(
      'produces non-empty bytes starting with the PDF file signature',
      () async {
        final bytes = await buildAccountStatementPdfBytes(data);

        expect(bytes, isNotEmpty);
        // PDF files start with "%PDF-".
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      },
    );

    // `package:pdf` emits each word of a pw.Text as its own text-show token
    // in the content stream rather than one contiguous run, so multi-word
    // phrases are asserted word-by-word instead of as a joined substring.
    test(
      'includes the brand name, document title, and generation date',
      () async {
        final bytes = await buildAccountStatementPdfBytes(data);
        final text = String.fromCharCodes(bytes);

        expect(text, contains('(Indigo)'));
        expect(text, contains('(Loom)'));
        expect(text, contains('(Account)'));
        expect(text, contains('(Statement)'));
        expect(text, contains('(Generated:)'));
        expect(text, contains('(Oct)'));
        expect(text, contains('(30,)'));
        expect(text, contains('(2023)'));
      },
    );

    test('includes the balance and credit figures with no hardcoded "\$" and '
        'no derived credit-limit/total figure', () async {
      final bytes = await buildAccountStatementPdfBytes(data);
      final text = String.fromCharCodes(bytes);

      expect(text, contains('(?)'));
      expect(text, contains('(36,711.73)'));
      expect(text, contains('(Available)'));
      expect(text, contains('(57,150.00)'));
      expect(text, contains('(Used)'));
      expect(text, contains('(42,850.00)'));
      expect(text, isNot(contains(r'($36,711.73)')));
      // No inferred total (availableCredit + usedCredit = 100,000.00) and
      // no "Credit Limit" label — that figure isn't a confirmed backend
      // contract.
      expect(text, isNot(contains('(100,000.00)')));
      expect(text, isNot(contains('(Limit)')));
    });

    test('includes the selected Balance History From/To range as a label '
        'only — Balance History rows themselves are never duplicated into '
        'the statement', () async {
      final bytes = await buildAccountStatementPdfBytes(data);
      final text = String.fromCharCodes(bytes);

      expect(text, contains('(HISTORY)'));
      expect(text, contains('(Oct)'));
      expect(text, contains('(1,)'));
      expect(text, contains('(30,)'));
    });

    test(
      'includes no Quick History section when there are no transactions',
      () async {
        final bytes = await buildAccountStatementPdfBytes(data);
        final text = String.fromCharCodes(bytes);

        expect(text, isNot(contains('(QUICK)')));
      },
    );

    test('includes the live Quick History transactions when present', () async {
      final dataWithHistory = AccountStatementData(
        customerBalance: data.customerBalance,
        creditUtilization: data.creditUtilization,
        historyFrom: data.historyFrom,
        historyTo: data.historyTo,
        quickHistory: [
          AccountTransaction(
            id: 'ledger-entry-1001',
            label: 'Invoice INV-TEST-001',
            amount: 100.50,
            type: AccountTransactionType.neutral,
            occurredAt: DateTime.utc(2026, 1, 5),
            category: AccountTransactionCategory.ledgerEntry,
            currencyCode: 'AED',
          ),
        ],
        generatedAt: data.generatedAt,
      );

      final bytes = await buildAccountStatementPdfBytes(dataWithHistory);
      final text = String.fromCharCodes(bytes);

      expect(text, contains('(QUICK)'));
      expect(text, contains('(Invoice)'));
      expect(text, contains('(AED)'));
      expect(text, contains('(100.50)'));
    });

    test('uses the passed-in currencyCode for the balance and credit figures, '
        'with no "?" fallback, agreeing with what the UI shows', () async {
      final aeData = AccountStatementData(
        customerBalance: data.customerBalance,
        creditUtilization: data.creditUtilization,
        historyFrom: data.historyFrom,
        historyTo: data.historyTo,
        generatedAt: data.generatedAt,
        currencyCode: 'AED',
      );

      final bytes = await buildAccountStatementPdfBytes(aeData);
      final text = String.fromCharCodes(bytes);

      expect(text, contains('(AED)'));
      expect(text, contains('(36,711.73)'));
      expect(text, contains('(57,150.00)'));
      expect(text, contains('(42,850.00)'));
      expect(text, isNot(contains('(?)')));
    });

    for (final currency in ['AED', 'OMR', 'USD', 'IQD', 'SYP']) {
      test(
        'A $currency currencyCode resolves to the $currency prefix',
        () async {
          final currencyData = AccountStatementData(
            customerBalance: data.customerBalance,
            creditUtilization: data.creditUtilization,
            historyFrom: data.historyFrom,
            historyTo: data.historyTo,
            generatedAt: data.generatedAt,
            currencyCode: currency,
          );

          final bytes = await buildAccountStatementPdfBytes(currencyData);
          final text = String.fromCharCodes(bytes);

          expect(text, contains('($currency)'));
        },
      );
    }
  });
}
