// Widget checks for the Account Transaction Details screen: header content,
// label/amount/status/date/reference display, optional reference omission,
// back navigation, and narrow-width overflow safety.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/screens/account_transaction_details_screen.dart';

final _creditTransaction = AccountTransaction(
  id: 'txn-client-deposit',
  label: 'Client Deposit',
  amount: 15000,
  type: AccountTransactionType.credit,
  occurredAt: DateTime.utc(2023, 10, 26),
  category: AccountTransactionCategory.deposit,
  reference: 'REF-20231026-CD',
);

final _debitTransaction = AccountTransaction(
  id: 'txn-loom-supply-42',
  label: 'Loom Supply #42',
  amount: -2400,
  type: AccountTransactionType.debit,
  occurredAt: DateTime.utc(2023, 10, 28),
  category: AccountTransactionCategory.supplyPurchase,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AccountTransaction transaction,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AccountTransactionDetailsScreen(transaction: transaction),
    ),
  );
}

void main() {
  group('Credit transaction', () {
    testWidgets(
      'Shows label, signed amount, Credit status, date, and reference',
      (tester) async {
        await _pumpScreen(tester, transaction: _creditTransaction);

        expect(find.text('Transaction Details'), findsOneWidget);
        expect(find.text('Client Deposit'), findsOneWidget);
        expect(find.text('+\$15,000'), findsOneWidget);
        expect(find.text('Credit'), findsOneWidget);
        expect(find.text('Oct 26, 2023'), findsOneWidget);
        expect(find.text('REF-20231026-CD'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Debit transaction without a reference', () {
    testWidgets('Shows Debit status and omits the Reference row', (
      tester,
    ) async {
      await _pumpScreen(tester, transaction: _debitTransaction);

      expect(find.text('Loom Supply #42'), findsOneWidget);
      expect(find.text('-\$2,400'), findsOneWidget);
      expect(find.text('Debit'), findsOneWidget);
      expect(find.text('Oct 28, 2023'), findsOneWidget);
      expect(find.text('Reference'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Back navigation', () {
    testWidgets('The menu/back button pops the screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AccountTransactionDetailsScreen(
                        transaction: _creditTransaction,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Transaction Details'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('account-transaction-details-menu-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transaction Details'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });
  });

  group('Responsive layout', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow at ${width}px width', (tester) async {
        await _pumpScreen(
          tester,
          transaction: _creditTransaction,
          width: width,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
