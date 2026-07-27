// Unit tests for adaptLedgerEntryToAccountTransaction: confirms
// LedgerEntry.currencyCode is preserved onto AccountTransaction rather than
// discarded, and that the amount is passed through unchanged.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/models/business_central/ledger_entry.dart';
import 'package:anc_fabrics/services/ledger_entry_presentation_adapter.dart';

LedgerEntry _entry({required String currencyCode, required double amount}) =>
    LedgerEntry(
      entryNo: 1001,
      postingDate: DateTime(2026, 1, 5),
      documentType: 'Invoice',
      documentNo: 'INV-53473',
      customerNo: 'CLNT-0001',
      customerName: 'Test Customer One',
      currencyCode: currencyCode,
      amount: amount,
      remainingAmount: amount,
      dueDate: DateTime(2026, 1, 15),
      isOpen: true,
    );

void main() {
  group('adaptLedgerEntryToAccountTransaction', () {
    test('preserves an AED Currency_Code onto AccountTransaction', () {
      final transaction = adaptLedgerEntryToAccountTransaction(
        _entry(currencyCode: 'AED', amount: 1936.5),
      );

      expect(transaction.currencyCode, 'AED');
    });

    test('preserves a USD Currency_Code onto AccountTransaction', () {
      final transaction = adaptLedgerEntryToAccountTransaction(
        _entry(currencyCode: 'USD', amount: 100.5),
      );

      expect(transaction.currencyCode, 'USD');
    });

    test('does not alter the ledger amount', () {
      final transaction = adaptLedgerEntryToAccountTransaction(
        _entry(currencyCode: 'AED', amount: 1936.5),
      );

      expect(transaction.amount, 1936.5);
    });

    test('renders neutral (never guesses credit/debit)', () {
      final transaction = adaptLedgerEntryToAccountTransaction(
        _entry(currencyCode: 'AED', amount: 1936.5),
      );

      expect(transaction.type, AccountTransactionType.neutral);
    });
  });
}
