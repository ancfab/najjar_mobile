// Focused widget checks for InvoiceActionButtons' loading states,
// independent of the full Invoice Details screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/widgets/invoice_action_buttons.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

Future<void> _pumpButtons(
  WidgetTester tester, {
  bool isPrinting = false,
  bool isDownloading = false,
  VoidCallback? onPrint,
  VoidCallback? onDownloadPdf,
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
        body: InvoiceActionButtons(
          onPrint: onPrint ?? () {},
          onDownloadPdf: onDownloadPdf ?? () {},
          isPrinting: isPrinting,
          isDownloading: isDownloading,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Shows Print/Download PDF labels when idle', (tester) async {
    await _pumpButtons(tester);

    expect(find.text('Print'), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invoice-action-print-loading')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('invoice-action-download-pdf-loading')),
      findsNothing,
    );
  });

  testWidgets('Shows a spinner in place of the Print label when printing', (
    tester,
  ) async {
    await _pumpButtons(tester, isPrinting: true);

    expect(find.text('Print'), findsNothing);
    expect(
      find.byKey(const ValueKey('invoice-action-print-loading')),
      findsOneWidget,
    );
    // Download PDF keeps its normal label but is disabled underneath.
    expect(find.text('Download PDF'), findsOneWidget);
  });

  testWidgets(
    'Shows a spinner in place of the Download PDF label when downloading',
    (tester) async {
      await _pumpButtons(tester, isDownloading: true);

      expect(find.text('Download PDF'), findsNothing);
      expect(
        find.byKey(const ValueKey('invoice-action-download-pdf-loading')),
        findsOneWidget,
      );
      expect(find.text('Print'), findsOneWidget);
    },
  );

  testWidgets('Does not call onPrint/onDownloadPdf while either is busy', (
    tester,
  ) async {
    var printTaps = 0;
    var downloadTaps = 0;
    await _pumpButtons(
      tester,
      isPrinting: true,
      onPrint: () => printTaps++,
      onDownloadPdf: () => downloadTaps++,
    );

    await tester.tap(find.byKey(const ValueKey('invoice-action-print-button')));
    await tester.tap(
      find.byKey(const ValueKey('invoice-action-download-pdf-button')),
    );
    await tester.pump();

    expect(printTaps, 0);
    expect(downloadTaps, 0);
  });

  testWidgets('Calls onPrint/onDownloadPdf when idle', (tester) async {
    var printTaps = 0;
    var downloadTaps = 0;
    await _pumpButtons(
      tester,
      onPrint: () => printTaps++,
      onDownloadPdf: () => downloadTaps++,
    );

    await tester.tap(find.text('Print'));
    await tester.tap(find.text('Download PDF'));
    await tester.pump();

    expect(printTaps, 1);
    expect(downloadTaps, 1);
  });
}
