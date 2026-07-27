// Focused widget checks for QuickHistoryCard, independent of the full
// Account Balance screen: header/chevron rendering, row content and
// styling, tap callbacks, and narrow-width overflow safety.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/theme/app_colors.dart';
import 'package:anc_fabrics/widgets/quick_history_card.dart';

final _transactions = [
  AccountTransaction(
    id: 'txn-loom-supply-42',
    label: 'Loom Supply #42',
    amount: -2400,
    type: AccountTransactionType.debit,
    occurredAt: DateTime(2023, 10, 28),
    category: AccountTransactionCategory.supplyPurchase,
  ),
  AccountTransaction(
    id: 'txn-client-deposit',
    label: 'Client Deposit',
    amount: 15000,
    type: AccountTransactionType.credit,
    occurredAt: DateTime(2023, 10, 26),
    category: AccountTransactionCategory.deposit,
    reference: 'REF-20231026-CD',
  ),
  AccountTransaction(
    id: 'txn-service-fee',
    label: 'Service Fee',
    amount: -120,
    type: AccountTransactionType.debit,
    occurredAt: DateTime(2023, 10, 24),
    category: AccountTransactionCategory.serviceFee,
  ),
];

Future<void> _pumpCard(
  WidgetTester tester, {
  List<AccountTransaction> transactions = const [],
  ValueChanged<AccountTransaction>? onTransactionTap,
  VoidCallback? onSeeAll,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuickHistoryCard(
            transactions: transactions,
            onTransactionTap: onTransactionTap ?? (_) {},
            onSeeAll: onSeeAll ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Header', () {
    testWidgets('Shows the QUICK HISTORY heading and a see-all chevron', (
      tester,
    ) async {
      await _pumpCard(tester, transactions: _transactions);

      expect(find.text('QUICK HISTORY'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick-history-see-all-button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('Tapping the chevron calls onSeeAll', (tester) async {
      var seeAllTapped = false;
      await _pumpCard(
        tester,
        transactions: _transactions,
        onSeeAll: () => seeAllTapped = true,
      );

      await tester.tap(
        find.byKey(const ValueKey('quick-history-see-all-button')),
      );
      await tester.pump();

      expect(seeAllTapped, isTrue);
    });
  });

  group('Rows', () {
    testWidgets('Shows each transaction label and signed amount', (
      tester,
    ) async {
      await _pumpCard(tester, transactions: _transactions);

      expect(find.text('Loom Supply #42'), findsOneWidget);
      expect(find.text('-\$2,400'), findsOneWidget);
      expect(find.text('Client Deposit'), findsOneWidget);
      expect(find.text('+\$15,000'), findsOneWidget);
      expect(find.text('Service Fee'), findsOneWidget);
      expect(find.text('-\$120'), findsOneWidget);
    });

    testWidgets(
      'Credit amounts are teal and debit amounts are dark red-brown',
      (tester) async {
        await _pumpCard(tester, transactions: _transactions);

        final creditAmount = tester.widget<Text>(find.text('+\$15,000'));
        expect(creditAmount.style?.color, AppColors.darkTeal);

        final debitAmount = tester.widget<Text>(find.text('-\$2,400'));
        expect(debitAmount.style?.color, AppColors.darkRedBrown);
      },
    );

    testWidgets('Tapping a row calls onTransactionTap with that transaction', (
      tester,
    ) async {
      AccountTransaction? tapped;
      await _pumpCard(
        tester,
        transactions: _transactions,
        onTransactionTap: (transaction) => tapped = transaction,
      );

      await tester.tap(
        find.byKey(const ValueKey('quick-history-row-txn-client-deposit')),
      );
      await tester.pump();

      expect(tapped?.id, 'txn-client-deposit');
    });

    testWidgets('Renders without crashing when there are no transactions yet', (
      tester,
    ) async {
      await _pumpCard(tester, transactions: const []);

      expect(find.text('QUICK HISTORY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Neutral rows (e.g. Business Central ledger entries)', () {
    final neutralTransaction = AccountTransaction(
      id: 'ledger-entry-1001',
      label: 'Invoice INV-TEST-001',
      amount: 100.50,
      type: AccountTransactionType.neutral,
      occurredAt: DateTime(2026, 1, 5),
      category: AccountTransactionCategory.ledgerEntry,
      reference: 'INV-TEST-001',
    );

    testWidgets(
      'Shows a plain (non-signed) amount in the neutral navy color, not the '
      'credit/debit colors',
      (tester) async {
        await _pumpCard(tester, transactions: [neutralTransaction]);

        expect(find.text('Invoice INV-TEST-001'), findsOneWidget);
        final amountText = tester.widget<Text>(find.text('\$100.50'));
        expect(amountText.style?.color, AppColors.textNavy);
        expect(find.text('+\$101'), findsNothing);
      },
    );

    testWidgets('A negative neutral amount shows a literal minus, not a '
        'forced +/- sign', (tester) async {
      final negativeNeutral = AccountTransaction(
        id: 'ledger-entry-1002',
        label: 'Payment PAY-TEST-002',
        amount: -50.00,
        type: AccountTransactionType.neutral,
        occurredAt: DateTime(2026, 1, 3),
        category: AccountTransactionCategory.ledgerEntry,
      );

      await _pumpCard(tester, transactions: [negativeNeutral]);

      expect(find.text('-\$50.00'), findsOneWidget);
    });

    testWidgets('An AED ledger entry renders with the AED currency code, '
        'not a dollar sign', (tester) async {
      final aedTransaction = AccountTransaction(
        id: 'ledger-entry-53473',
        label: 'Invoice INV-53473',
        amount: 1936.5,
        type: AccountTransactionType.neutral,
        occurredAt: DateTime(2026, 1, 5),
        category: AccountTransactionCategory.ledgerEntry,
        reference: 'INV-53473',
        currencyCode: 'AED',
      );

      await _pumpCard(tester, transactions: [aedTransaction]);

      expect(find.text('AED 1,936.50'), findsOneWidget);
      expect(find.text('\$1,936.50'), findsNothing);
      expect(find.textContaining('\$'), findsNothing);
    });

    testWidgets('A USD ledger entry renders with the USD currency code, '
        'not a dollar sign', (tester) async {
      final usdTransaction = AccountTransaction(
        id: 'ledger-entry-1004',
        label: 'Invoice INV-TEST-004',
        amount: 250.0,
        type: AccountTransactionType.neutral,
        occurredAt: DateTime(2026, 1, 6),
        category: AccountTransactionCategory.ledgerEntry,
        currencyCode: 'USD',
      );

      await _pumpCard(tester, transactions: [usdTransaction]);

      expect(find.text('USD 250.00'), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing);
    });
  });

  group('Responsive layout', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow at ${width}px width', (tester) async {
        await _pumpCard(tester, transactions: _transactions, width: width);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
