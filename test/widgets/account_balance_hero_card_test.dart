// Focused widget checks for AccountBalanceHeroCard, independent of the full
// Account Balance screen: balance rendering (no hardcoded "$", via
// formatCurrencyOrUnknown), and the Export PDF button's tap callback and
// its Generating... loading state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/widgets/account_balance_hero_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required double balance,
  VoidCallback? onExportPdf,
  bool isExporting = false,
  double width = 390,
  String? currencyCode,
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
      home: Scaffold(
        body: AccountBalanceHeroCard(
          balance: balance,
          onExportPdf: onExportPdf ?? () {},
          isExporting: isExporting,
          currencyCode: currencyCode,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Balance', () {
    testWidgets(
      'Shows the plain balance, no prefix (no known currency), not "\$"',
      (tester) async {
        await _pumpCard(tester, balance: 36711.73);

        expect(find.text('36,711.73'), findsOneWidget);
        expect(find.text('\$36,711.73'), findsNothing);
      },
    );

    testWidgets('Never shows the retired mock percent-change text', (
      tester,
    ) async {
      await _pumpCard(tester, balance: 36711.73);

      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('from last month'), findsNothing);
    });

    testWidgets('Shows the passed-in currencyCode when supplied', (
      tester,
    ) async {
      await _pumpCard(tester, balance: 36711.73, currencyCode: 'AED');

      expect(find.text('AED 36,711.73'), findsOneWidget);
      expect(find.text('36,711.73'), findsNothing);
    });

    for (final currency in ['AED', 'OMR', 'USD', 'IQD', 'SYP']) {
      testWidgets('A $currency currencyCode renders the $currency prefix', (
        tester,
      ) async {
        await _pumpCard(tester, balance: 36711.73, currencyCode: currency);

        expect(find.text('$currency 36,711.73'), findsOneWidget);
      });
    }
  });

  group('Export PDF button', () {
    testWidgets('Calls onExportPdf when tapped', (tester) async {
      var tapped = false;
      await _pumpCard(
        tester,
        balance: 36711.73,
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
      await _pumpCard(tester, balance: 36711.73, isExporting: true);

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
        balance: 36711.73,
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
          balance: 36711.73,
          isExporting: true,
          width: width,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
