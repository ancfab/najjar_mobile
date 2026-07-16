// Unit tests for buildAccountStatementPdfBytes: verifies it produces a
// real, non-empty PDF document containing the required Account Statement
// text and figures, without depending on any platform plugin.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/account_balance_summary.dart';
import 'package:anc_fabrics/models/account_statement_data.dart';
import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/models/balance_history_range.dart';
import 'package:anc_fabrics/models/credit_utilization_data.dart';
import 'package:anc_fabrics/services/account_statement_exporter.dart';

void main() {
  final data = AccountStatementData(
    summary: const AccountBalanceSummary(
      currentBalance: 42850.00,
      percentChangeFromLastMonth: 12.4,
      changePeriodLabel: 'from last month',
    ),
    creditUtilization: const CreditUtilizationData(
      totalCredit: 100000.00,
      availableCredit: 57150.00,
      usedCredit: 42850.00,
    ),
    selectedRange: BalanceHistoryRange.ninetyDays,
    quickHistory: [
      AccountTransaction(
        id: 'txn-client-deposit',
        label: 'Client Deposit',
        amount: 15000,
        type: AccountTransactionType.credit,
        occurredAt: DateTime.utc(2023, 10, 26),
        category: AccountTransactionCategory.deposit,
      ),
      AccountTransaction(
        id: 'txn-loom-supply-42',
        label: 'Loom Supply #42',
        amount: -2400,
        type: AccountTransactionType.debit,
        occurredAt: DateTime.utc(2023, 10, 28),
        category: AccountTransactionCategory.supplyPurchase,
      ),
    ],
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

    test('includes the balance, percent change, and credit figures', () async {
      final bytes = await buildAccountStatementPdfBytes(data);
      final text = String.fromCharCodes(bytes);

      expect(text, contains(r'($42,850.00)'));
      expect(text, contains('(+12.4%)'));
      expect(text, contains('(Available)'));
      expect(text, contains(r'($57,150.00)'));
      expect(text, contains('(Used)'));
      expect(text, contains(r'($42,850.00)'));
      expect(text, contains('(Credit)'));
      expect(text, contains('(Limit)'));
      expect(text, contains(r'($100,000.00)'));
    });

    test('includes the selected Balance History range label', () async {
      final bytes = await buildAccountStatementPdfBytes(data);
      final text = String.fromCharCodes(bytes);

      expect(text, contains('(90)'));
      expect(text, contains('(Days)'));
    });

    test(
      'includes Quick History transaction rows with signed amounts',
      () async {
        final bytes = await buildAccountStatementPdfBytes(data);
        final text = String.fromCharCodes(bytes);

        expect(text, contains('(Client)'));
        expect(text, contains('(Deposit)'));
        expect(text, contains('(+\$15,000)'));
        expect(text, contains('(Loom)'));
        expect(text, contains('(Supply)'));
        expect(text, contains('(#42)'));
        expect(text, contains('(-\$2,400)'));
      },
    );

    test('succeeds when Quick History has no transactions', () async {
      final emptyHistoryData = AccountStatementData(
        summary: data.summary,
        creditUtilization: data.creditUtilization,
        selectedRange: data.selectedRange,
        quickHistory: const [],
        generatedAt: data.generatedAt,
      );

      final bytes = await buildAccountStatementPdfBytes(emptyHistoryData);

      expect(bytes, isNotEmpty);
    });
  });
}
