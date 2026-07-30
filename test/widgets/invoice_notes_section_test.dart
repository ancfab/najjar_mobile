// Focused widget checks for the reusable InvoiceNotesSection component,
// independent of the full Invoice Details screen: heading/note rendering and
// empty-state safety.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/widgets/invoice_notes_section.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

Future<void> _pumpSection(WidgetTester tester, String? note) async {
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: InvoiceNotesSection(note: note)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Renders the heading and note text', (tester) async {
    await _pumpSection(tester, 'Please pay via bank transfer only.');

    expect(find.text('Internal Notes'), findsOneWidget);
    expect(find.text('Please pay via bank transfer only.'), findsOneWidget);
  });

  testWidgets('Renders nothing for a null note', (tester) async {
    await _pumpSection(tester, null);

    expect(find.text('Internal Notes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Renders nothing for an empty or whitespace-only note', (
    tester,
  ) async {
    await _pumpSection(tester, '   ');

    expect(find.text('Internal Notes'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
