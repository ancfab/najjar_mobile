// Focused widget checks for AccountBalanceHeroCard, independent of the full
// Account Balance screen: balance/percent-change rendering for both
// positive and negative changes, the Export PDF button's tap callback, and
// its Generating... loading state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/widgets/account_balance_hero_card.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required double balance,
  required double percentChange,
  VoidCallback? onExportPdf,
  bool isExporting = false,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AccountBalanceHeroCard(
          balance: balance,
          percentChange: percentChange,
          changePeriodLabel: 'from last month',
          onExportPdf: onExportPdf ?? () {},
          isExporting: isExporting,
        ),
      ),
    ),
  );
}

void main() {
  group('Positive change', () {
    testWidgets('Shows the balance, a "+" prefixed change, and an up icon', (
      tester,
    ) async {
      await _pumpCard(tester, balance: 42850.00, percentChange: 12.4);

      expect(find.text('\$42,850.00'), findsOneWidget);
      expect(find.text('+12.4% from last month'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    });
  });

  group('Negative change', () {
    testWidgets('Shows an unprefixed negative change and a down icon', (
      tester,
    ) async {
      await _pumpCard(tester, balance: 10000.00, percentChange: -5.2);

      expect(find.text('-5.2% from last month'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
    });
  });

  group('Export PDF button', () {
    testWidgets('Calls onExportPdf when tapped', (tester) async {
      var tapped = false;
      await _pumpCard(
        tester,
        balance: 42850.00,
        percentChange: 12.4,
        onExportPdf: () => tapped = true,
      );

      await tester.tap(find.text('Export PDF'));
      await tester.pump();

      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shows Generating... and a spinner while isExporting is true', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        balance: 42850.00,
        percentChange: 12.4,
        isExporting: true,
      );

      expect(find.text('Generating...'), findsOneWidget);
      expect(find.text('Export PDF'), findsNothing);
      expect(
        find.byKey(const ValueKey('account-balance-export-pdf-loading')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Disables the button while isExporting is true', (
      tester,
    ) async {
      var tapCount = 0;
      await _pumpCard(
        tester,
        balance: 42850.00,
        percentChange: 12.4,
        onExportPdf: () => tapCount++,
        isExporting: true,
      );

      final button = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('account-balance-export-pdf-button')),
      );
      expect(button.onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('account-balance-export-pdf-button')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(tapCount, 0);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow while isExporting is true at ${width}px width', (
        tester,
      ) async {
        await _pumpCard(
          tester,
          balance: 42850.00,
          percentChange: 12.4,
          isExporting: true,
          width: width,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
