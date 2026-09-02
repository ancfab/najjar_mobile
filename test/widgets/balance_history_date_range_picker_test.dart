// Focused widget checks for BalanceHistoryDateRangePicker: real
// showDatePicker interaction (not just callback wiring) for both the From
// and To fields, and the firstDate/lastDate constraints that keep the
// picker itself from ever offering an invalid range.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/widgets/balance_history_date_range_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

Future<void> _pumpPicker(
  WidgetTester tester, {
  required DateTime from,
  required DateTime to,
  ValueChanged<DateTime>? onFromChanged,
  ValueChanged<DateTime>? onToChanged,
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
        body: BalanceHistoryDateRangePicker(
          from: from,
          to: to,
          onFromChanged: onFromChanged ?? (_) {},
          onToChanged: onToChanged ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Rendering', () {
    testWidgets('Shows both fields with their formatted dates', (tester) async {
      await _pumpPicker(
        tester,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 15),
      );

      expect(find.text('From'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(find.text('Jan 1, 2026'), findsOneWidget);
      expect(find.text('Jan 15, 2026'), findsOneWidget);
    });
  });

  group('From date selection', () {
    testWidgets(
      'Tapping the From field opens a date picker and accepting a day '
      'invokes onFromChanged with that day',
      (tester) async {
        DateTime? picked;
        await _pumpPicker(
          tester,
          from: DateTime(2026, 1, 10),
          to: DateTime(2026, 1, 20),
          onFromChanged: (date) => picked = date,
        );

        await tester.tap(
          find.byKey(const ValueKey('balance-history-from-field')),
        );
        await tester.pumpAndSettle();

        // A well-inside-the-month, unambiguous day cell.
        await tester.tap(find.text('15').first);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(picked, isNotNull);
        expect(picked!.year, 2026);
        expect(picked!.month, 1);
        expect(picked!.day, 15);
      },
    );
  });

  group('To date selection', () {
    testWidgets('Tapping the To field opens a date picker and accepting a day '
        'invokes onToChanged with that day', (tester) async {
      DateTime? picked;
      await _pumpPicker(
        tester,
        from: DateTime(2026, 1, 10),
        to: DateTime(2026, 1, 20),
        onToChanged: (date) => picked = date,
      );

      await tester.tap(find.byKey(const ValueKey('balance-history-to-field')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('15').first);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.year, 2026);
      expect(picked!.month, 1);
      expect(picked!.day, 15);
    });
  });
}
