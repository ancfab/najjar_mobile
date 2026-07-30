// Widget checks for the Account Transaction Details screen: header content,
// label/amount/status/date/reference display, optional reference omission,
// back navigation, and narrow-width overflow safety.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/screens/account_transaction_details_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

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
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AccountTransactionDetailsScreen(transaction: transaction),
    ),
  );
  await tester.pump();
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

  group('Neutral transaction (e.g. a Business Central ledger entry)', () {
    final neutralTransaction = AccountTransaction(
      id: 'ledger-entry-1001',
      label: 'Invoice INV-TEST-001',
      amount: 100.50,
      type: AccountTransactionType.neutral,
      occurredAt: DateTime.utc(2026, 1, 5),
      category: AccountTransactionCategory.ledgerEntry,
      reference: 'INV-TEST-001',
    );

    testWidgets(
      'Shows a plain amount with no invented Credit/Debit status line',
      (tester) async {
        await _pumpScreen(tester, transaction: neutralTransaction);

        expect(find.text('Invoice INV-TEST-001'), findsOneWidget);
        expect(find.text('\$100.50'), findsOneWidget);
        expect(find.text('Credit'), findsNothing);
        expect(find.text('Debit'), findsNothing);
        expect(find.text('Jan 5, 2026'), findsOneWidget);
        expect(find.text('INV-TEST-001'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'An AED ledger entry shows the AED currency code, not a dollar sign',
      (tester) async {
        final aedTransaction = AccountTransaction(
          id: 'ledger-entry-53473',
          label: 'Invoice INV-53473',
          amount: 1936.5,
          type: AccountTransactionType.neutral,
          occurredAt: DateTime.utc(2026, 1, 5),
          category: AccountTransactionCategory.ledgerEntry,
          reference: 'INV-53473',
          currencyCode: 'AED',
        );

        await _pumpScreen(tester, transaction: aedTransaction);

        expect(find.text('AED 1,936.50'), findsOneWidget);
        expect(find.textContaining('\$'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'A USD ledger entry shows the USD currency code, not a dollar sign',
      (tester) async {
        final usdTransaction = AccountTransaction(
          id: 'ledger-entry-1004',
          label: 'Invoice INV-TEST-004',
          amount: 250.0,
          type: AccountTransactionType.neutral,
          occurredAt: DateTime.utc(2026, 1, 6),
          category: AccountTransactionCategory.ledgerEntry,
          currencyCode: 'USD',
        );

        await _pumpScreen(tester, transaction: usdTransaction);

        expect(find.text('USD 250.00'), findsOneWidget);
        expect(find.textContaining('\$'), findsNothing);
      },
    );
  });

  group('Back navigation', () {
    testWidgets('The menu/back button pops the screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
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
      await tester.pump();

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
