// Widget checks for the Account Balance screen: hero card figures, credit
// utilization figures and note, the Balance History range selector/chart,
// the Export PDF placeholder action, bottom navigation, and narrow-width
// overflow safety.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/theme/app_colors.dart';

import 'helpers/fake_account_balance_service.dart';

Future<void> _pumpAccountBalanceScreen(
  WidgetTester tester, {
  double width = 390,
  FakeAccountBalanceService? service,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AccountBalanceScreen(
        service: service ?? FakeAccountBalanceService(),
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

  group('Export PDF', () {
    testWidgets(
      'Tapping Export PDF shows a placeholder message without crashing',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        await tester.tap(find.text('Export PDF'));
        await tester.pumpAndSettle();

        expect(find.text('PDF export is not connected yet.'), findsOneWidget);
        expect(tester.takeException(), isNull);
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
  });

  group('Scope restriction', () {
    testWidgets('Does not render a Quick History section', (tester) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.text('Quick History'), findsNothing);
      expect(find.textContaining('QUICK HISTORY'), findsNothing);
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
