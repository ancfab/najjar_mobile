// Focused widget checks for CreditUtilizationCard, independent of the full
// Account Balance screen: figure rendering, progress-bar widths calculated
// from the supplied ratios, and the credit-limit-change note's empty-state
// safety.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/credit_utilization_data.dart';
import 'package:anc_fabrics/widgets/credit_utilization_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

Future<void> _pumpCard(WidgetTester tester, CreditUtilizationData data) async {
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: CreditUtilizationCard(data: data)),
    ),
  );
  await tester.pump();
}

void main() {
  group('Figures', () {
    testWidgets('Shows Available Credit and Used Credit labels and values', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(
          totalCredit: 100000.00,
          availableCredit: 57150.00,
          usedCredit: 42850.00,
        ),
      );

      expect(find.text('Available Credit'), findsOneWidget);
      expect(find.text('\$57,150.00'), findsOneWidget);
      expect(find.text('Used Credit'), findsOneWidget);
      expect(find.text('\$42,850.00'), findsOneWidget);
    });
  });

  group('Progress bars', () {
    testWidgets('Available Credit bar is wider when its ratio is higher', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(
          totalCredit: 100000.00,
          availableCredit: 57150.00,
          usedCredit: 42850.00,
        ),
      );

      final availableBarWidth = tester
          .getSize(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('credit-utilization-available-row'),
                  ),
                  matching: find.byType(Container),
                )
                .at(1),
          )
          .width;
      final usedBarWidth = tester
          .getSize(
            find
                .descendant(
                  of: find.byKey(const ValueKey('credit-utilization-used-row')),
                  matching: find.byType(Container),
                )
                .at(1),
          )
          .width;

      expect(availableBarWidth, greaterThan(usedBarWidth));
      expect(tester.takeException(), isNull);
    });
  });

  group('Credit-limit-change note', () {
    testWidgets('Renders the note text when present', (tester) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(
          totalCredit: 100000.00,
          availableCredit: 57150.00,
          usedCredit: 42850.00,
          creditLimitChangeNote:
              'Your credit limit was recently increased by \$10,000 on Oct 12.',
        ),
      );

      expect(
        find.text(
          'Your credit limit was recently increased by \$10,000 on Oct 12.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Renders nothing when the note is null', (tester) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(
          totalCredit: 100000.00,
          availableCredit: 57150.00,
          usedCredit: 42850.00,
        ),
      );

      expect(
        find.byKey(const ValueKey('credit-utilization-note')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders nothing when the note is blank', (tester) async {
      await _pumpCard(
        tester,
        const CreditUtilizationData(
          totalCredit: 100000.00,
          availableCredit: 57150.00,
          usedCredit: 42850.00,
          creditLimitChangeNote: '   ',
        ),
      );

      expect(
        find.byKey(const ValueKey('credit-utilization-note')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
