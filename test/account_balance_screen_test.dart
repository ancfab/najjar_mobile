// Widget checks for the Account Balance screen: hero card figures, credit
// utilization figures and note, the Balance History range selector/chart,
// the Quick History list (rendering, styling, row/see-all navigation), the
// Export PDF flow (loading state, duplicate-tap guard, success/failure
// handling, and the data handed to the exporter), bottom navigation, and
// narrow-width overflow safety.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/balance_history_range.dart';
import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/profile_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/theme/app_colors.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';

import 'helpers/fake_account_balance_service.dart';
import 'helpers/fake_account_statement_exporter.dart';

Future<void> _pumpAccountBalanceScreen(
  WidgetTester tester, {
  double width = 390,
  FakeAccountBalanceService? service,
  FakeAccountStatementExporter? exporter,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AccountBalanceScreen(
        service: service ?? FakeAccountBalanceService(),
        exporter: exporter ?? FakeAccountStatementExporter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Renders without exceptions', () {
    testWidgets('Builds successfully with mock data', (tester) async {
      await _pumpAccountBalanceScreen(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Header', () {
    testWidgets('Shows the Indigo Loom brand and avatar initials badge', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.text('Indigo Loom'), findsOneWidget);
      // Derived from the mock signed-in user, "Alex Sterling".
      expect(find.text('AS'), findsOneWidget);
    });
  });

  group('Global Account Balance hero card', () {
    testWidgets('Shows the balance, percent change, and Export PDF button', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.text('\$42,850.00'), findsWidgets);
      expect(find.text('+12.4% from last month'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
    });
  });

  group('Credit Utilization card', () {
    testWidgets('Shows the Available Credit and Used Credit values', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.text('Available Credit'), findsOneWidget);
      expect(find.text('\$57,150.00'), findsOneWidget);
      expect(find.text('Used Credit'), findsOneWidget);
      // $42,850.00 appears twice: once as the hero balance, once as Used
      // Credit (matching the mock data, where they're equal).
      expect(find.text('\$42,850.00'), findsNWidgets(2));
    });

    testWidgets('Shows the credit-limit-change note', (tester) async {
      await _pumpAccountBalanceScreen(tester);

      expect(
        find.text(
          'Your credit limit was recently increased by \$10,000 on Oct 12.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Balance History card', () {
    testWidgets(
      'Renders all three range options with 30 Days selected initially',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        expect(find.text('30 Days'), findsOneWidget);
        expect(find.text('90 Days'), findsOneWidget);
        expect(find.text('1 Year'), findsOneWidget);
        expect(
          find.text('Trend analysis for Oct 1 - Oct 30, 2023'),
          findsOneWidget,
        );
      },
    );

    testWidgets('30 Days segment uses the dark navy selected treatment', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('balance-history-range-thirtyDays')),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.primaryNavy);
    });

    testWidgets('Selecting 90 Days updates the selected state and dataset', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      await tester.tap(find.text('90 Days'));
      await tester.pumpAndSettle();

      expect(
        find.text('Trend analysis for Aug 2 - Oct 30, 2023'),
        findsOneWidget,
      );
      expect(
        find.text('Trend analysis for Oct 1 - Oct 30, 2023'),
        findsNothing,
      );

      final selected = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('balance-history-range-ninetyDays')),
          matching: find.byType(Container),
        ),
      );
      expect(
        (selected.decoration as BoxDecoration).color,
        AppColors.primaryNavy,
      );

      final unselected = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('balance-history-range-thirtyDays')),
          matching: find.byType(Container),
        ),
      );
      expect(
        (unselected.decoration as BoxDecoration).color,
        Colors.transparent,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Selecting 1 Year updates the selected state and dataset', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      await tester.tap(find.text('1 Year'));
      await tester.pumpAndSettle();

      expect(
        find.text('Trend analysis for Oct 30, 2022 - Oct 30, 2023'),
        findsOneWidget,
      );

      final selected = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('balance-history-range-oneYear')),
          matching: find.byType(Container),
        ),
      );
      expect(
        (selected.decoration as BoxDecoration).color,
        AppColors.primaryNavy,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Quick History card', () {
    testWidgets(
      'Renders below the Balance History card with all mock transactions',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        expect(find.text('QUICK HISTORY'), findsOneWidget);

        final balanceHistoryTop = tester.getTopLeft(
          find.byKey(const ValueKey('balance-history-card')),
        );
        final quickHistoryTop = tester.getTopLeft(
          find.byKey(const ValueKey('quick-history-card')),
        );
        expect(quickHistoryTop.dy, greaterThan(balanceHistoryTop.dy));

        expect(find.text('Loom Supply #42'), findsOneWidget);
        expect(find.text('Client Deposit'), findsOneWidget);
        expect(find.text('Service Fee'), findsOneWidget);
        expect(find.text('-\$2,400'), findsOneWidget);
        expect(find.text('+\$15,000'), findsOneWidget);
        expect(find.text('-\$120'), findsOneWidget);
      },
    );

    testWidgets(
      'Credit amounts use the teal color and debit amounts use the dark debit color',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        final creditText = tester.widget<Text>(find.text('+\$15,000'));
        expect(creditText.style?.color, AppColors.darkTeal);

        final debitText = tester.widget<Text>(find.text('-\$2,400'));
        expect(debitText.style?.color, AppColors.darkRedBrown);

        final feeText = tester.widget<Text>(find.text('-\$120'));
        expect(feeText.style?.color, AppColors.darkRedBrown);
      },
    );

    testWidgets(
      'Tapping a row opens Transaction Details with the selected transaction',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        final row = find.byKey(
          const ValueKey('quick-history-row-txn-client-deposit'),
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(find.text('Transaction Details'), findsOneWidget);

        final detailsCard = find.byKey(
          const ValueKey('account-transaction-details-card'),
        );
        expect(
          find.descendant(
            of: detailsCard,
            matching: find.text('Client Deposit'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: detailsCard, matching: find.text('+\$15,000')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: detailsCard, matching: find.text('Credit')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: detailsCard,
            matching: find.text('REF-20231026-CD'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Tapping a debit row opens Transaction Details showing Debit status',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        final row = find.byKey(
          const ValueKey('quick-history-row-txn-loom-supply-42'),
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();

        final detailsCard = find.byKey(
          const ValueKey('account-transaction-details-card'),
        );
        expect(
          find.descendant(
            of: detailsCard,
            matching: find.text('Loom Supply #42'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: detailsCard, matching: find.text('-\$2,400')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: detailsCard, matching: find.text('Debit')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Tapping See all shows the temporary placeholder SnackBar', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      final seeAllButton = find.byKey(
        const ValueKey('quick-history-see-all-button'),
      );
      await tester.ensureVisible(seeAllButton);
      await tester.tap(seeAllButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Full transaction history is not available yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Export PDF', () {
    testWidgets('Tapping Export PDF invokes the injected exporter', (
      tester,
    ) async {
      final exporter = FakeAccountStatementExporter();
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      expect(exporter.exportedData, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shows Generating... while export is pending', (tester) async {
      final pending = Completer<void>();
      final exporter = FakeAccountStatementExporter(pending: pending);
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pump();

      expect(find.text('Generating...'), findsOneWidget);
      expect(find.text('Export PDF'), findsNothing);

      pending.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Disables the button while export is pending', (tester) async {
      final pending = Completer<void>();
      final exporter = FakeAccountStatementExporter(pending: pending);
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('account-balance-export-pdf-button')),
      );
      expect(button.onPressed, isNull);

      pending.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Repeated taps while pending do not invoke duplicate exports', (
      tester,
    ) async {
      final pending = Completer<void>();
      final exporter = FakeAccountStatementExporter(pending: pending);
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      final exportButton = find.byKey(
        const ValueKey('account-balance-export-pdf-button'),
      );
      await tester.tap(exportButton);
      await tester.pump();
      await tester.tap(exportButton, warnIfMissed: false);
      await tester.tap(exportButton, warnIfMissed: false);
      await tester.pump();

      expect(exporter.exportedData, hasLength(1));

      pending.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Successful export restores the normal Export PDF state', (
      tester,
    ) async {
      final exporter = FakeAccountStatementExporter();
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Generating...'), findsNothing);
      final button = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('account-balance-export-pdf-button')),
      );
      expect(button.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Failed export restores the normal Export PDF state', (
      tester,
    ) async {
      final exporter = FakeAccountStatementExporter(
        error: Exception('platform failure'),
      );
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Generating...'), findsNothing);
      final button = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('account-balance-export-pdf-button')),
      );
      expect(button.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Failed export shows the expected SnackBar', (tester) async {
      final exporter = FakeAccountStatementExporter(
        error: Exception('platform failure'),
      );
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not generate the account statement. Please try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Exporter receives the correct balance summary data', (
      tester,
    ) async {
      final exporter = FakeAccountStatementExporter();
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      final data = exporter.exportedData.single;
      expect(data.summary.currentBalance, 42850.00);
      expect(data.summary.percentChangeFromLastMonth, 12.4);
      expect(data.creditUtilization.availableCredit, 57150.00);
      expect(data.creditUtilization.usedCredit, 42850.00);
      expect(data.creditUtilization.totalCredit, 100000.00);
    });

    testWidgets('Exporter receives the selected Balance History range', (
      tester,
    ) async {
      final exporter = FakeAccountStatementExporter();
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('90 Days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      final data = exporter.exportedData.single;
      expect(data.selectedRange, BalanceHistoryRange.ninetyDays);
    });

    testWidgets(
      'Exporter receives the Quick History transactions shown on screen',
      (tester) async {
        final exporter = FakeAccountStatementExporter();
        await _pumpAccountBalanceScreen(tester, exporter: exporter);

        await tester.tap(find.text('Export PDF'));
        await tester.pumpAndSettle();

        final data = exporter.exportedData.single;
        expect(data.quickHistory.map((t) => t.id), [
          'txn-loom-supply-42',
          'txn-client-deposit',
          'txn-service-fee',
        ]);
      },
    );
  });

  group('Bottom navigation', () {
    testWidgets('Shows the Home, Orders, Support, and Profile tabs', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Reuses CustomBottomNav with exactly four destinations', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.byType(CustomBottomNav), findsOneWidget);
      expect(find.byType(CustomBottomNavItem), findsNWidgets(4));
      expect(find.text('Account Balance'), findsNothing);
    });

    testWidgets(
      'Selecting Home is safe when there is no screen to pop back to',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountBalanceScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Selecting Orders, Support, and Profile pushes each screen', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(find.byType(SupportScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('Responsive layout', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow at ${width}px width', (tester) async {
        await _pumpAccountBalanceScreen(tester, width: width);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
