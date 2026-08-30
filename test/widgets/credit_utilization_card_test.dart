// Focused widget checks for CreditUtilizationCard, independent of the full
// Account Balance screen: figure rendering with the "Credit Utilization"
// heading, the passed-in currencyCode (or the "?" unknown-currency
// fallback), and the derived progress bars.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/credit_utilization_data.dart';
import 'package:anc_fabrics/widgets/credit_utilization_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  CreditUtilizationData data, {
  String? currencyCode,
}) async {
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
        body: CreditUtilizationCard(data: data, currencyCode: currencyCode),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Figures', () {
    testWidgets(
      'Shows the Credit Utilization heading and Available/Used Credit '
      'labels, with the "?" unknown-currency fallback when no currency is '
      'supplied',
      (tester) async {
        await _pumpCard(
          tester,
          const CreditUtilizationData(
            availableCredit: 57150.00,
            usedCredit: 42850.00,
          ),
        );

        expect(find.text('Credit Utilization'), findsOneWidget);
        expect(find.text('Credit Information'), findsNothing);
        expect(find.text('Available Credit'), findsOneWidget);
        expect(find.text('? 57,150.00'), findsOneWidget);
        expect(find.text('Used Credit'), findsOneWidget);
        expect(find.text('? 42,850.00'), findsOneWidget);
        expect(find.text('\$57,150.00'), findsNothing);
        expect(find.text('\$42,850.00'), findsNothing);
      },
    );

    testWidgets('Shows the passed-in currencyCode when supplied', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(
          availableCredit: 57150.00,
          usedCredit: 42850.00,
        ),
        currencyCode: 'AED',
      );

      expect(find.text('AED 57,150.00'), findsOneWidget);
      expect(find.text('AED 42,850.00'), findsOneWidget);
      expect(find.text('? 57,150.00'), findsNothing);
    });

    for (final currency in ['AED', 'OMR', 'USD', 'IQD', 'SYP']) {
      testWidgets('A $currency currencyCode renders the $currency prefix', (
        tester,
      ) async {
        await _pumpCard(
          tester,
          const CreditUtilizationData(availableCredit: 0, usedCredit: 36711.73),
          currencyCode: currency,
        );

        expect(find.text('$currency 0.00'), findsOneWidget);
        expect(find.text('$currency 36,711.73'), findsOneWidget);
      });
    }

    testWidgets('Renders correctly with no exception even when '
        'availableCredit is 0', (tester) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(availableCredit: 0, usedCredit: 36711.73),
        currencyCode: 'AED',
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Progress bars', () {
    testWidgets('Renders a progress bar for each of the two rows', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(
          availableCredit: 57150.00,
          usedCredit: 42850.00,
        ),
      );

      expect(
        find.byKey(const ValueKey('credit-utilization-progress-bar')),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('No credit-limit-change note', () {
    testWidgets(
      'Never renders a note container (removed — no confirmed backend field)',
      (tester) async {
        await _pumpCard(
          tester,
          const CreditUtilizationData(
            availableCredit: 57150.00,
            usedCredit: 42850.00,
          ),
        );

        expect(
          find.byKey(const ValueKey('credit-utilization-note')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
