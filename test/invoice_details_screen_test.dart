// Widget checks for the Invoice Details screen: title, breadcrumb, PAID
// status badge, invoice number/issued date, Print/Download PDF actions,
// Billed To/Due Date/Payment Method sections, narrow-width overflow safety,
// and scrolling to the Payment Method section.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/screens/invoice_details_screen.dart';

/// The mock Invoice Details fetch has a simulated 400ms network delay;
/// `pumpAndSettle` alone won't wait for that bare `Future.delayed` since it
/// isn't tied to a scheduled frame.
Future<void> _settleFetch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<void> _pumpInvoiceDetailsScreen(
  WidgetTester tester, {
  String invoiceNumber = '#INV-8821',
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: InvoiceDetailsScreen(invoiceNumber: invoiceNumber)),
  );
  await _settleFetch(tester);
}

void main() {
  group('Header, breadcrumb, and title', () {
    testWidgets('Renders the Invoice Details title', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);
      expect(find.text('Invoice Details'), findsOneWidget);
    });

    testWidgets('Renders the breadcrumb with Invoices and the invoice number', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('Invoices'), findsOneWidget);
      // The invoice number appears twice: once in the breadcrumb and once
      // in the information card's summary row.
      expect(find.text('#INV-8821'), findsNWidgets(2));
    });
  });

  group('Invoice information card', () {
    testWidgets('Renders the PAID status badge', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);
      expect(find.text('PAID'), findsOneWidget);
    });

    testWidgets('Renders the invoice number and issued date', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('Invoice Number'), findsOneWidget);
      expect(find.text('#INV-8821'), findsNWidgets(2));
      expect(find.text('Issued Date'), findsOneWidget);
      expect(find.text('Oct 14, 2023'), findsOneWidget);
    });

    testWidgets('Renders the billed company, address, and email', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('BILLED TO'), findsOneWidget);
      expect(find.text('Luxury Linens Ltd.'), findsOneWidget);
      expect(find.text('882 High Street, Suite 402'), findsOneWidget);
      expect(find.text('London, W1J 7JX'), findsOneWidget);
      expect(find.text('United Kingdom'), findsOneWidget);
      expect(find.text('accounts@luxurylinens.com'), findsOneWidget);
    });

    testWidgets('Renders the due date', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('DUE DATE'), findsOneWidget);
      expect(find.text('Oct 28, 2023'), findsOneWidget);
    });

    testWidgets('Renders the payment method', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('PAYMENT METHOD'), findsOneWidget);
      expect(find.text('Bank Transfer (Ending ...4492)'), findsOneWidget);
    });
  });

  group('Print and Download PDF actions', () {
    testWidgets('Renders the Print and Download PDF buttons', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(
        find.byKey(const ValueKey('invoice-action-print-button')),
        findsOneWidget,
      );
      expect(find.text('Print'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('invoice-action-download-pdf-button')),
        findsOneWidget,
      );
      expect(find.text('Download PDF'), findsOneWidget);
    });

    testWidgets('Tapping Print shows the placeholder message safely', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);

      await tester.tap(find.text('Print'));
      await tester.pump();

      expect(
        find.text('Invoice printing is not available yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tapping Download PDF shows the placeholder message safely', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);

      await tester.tap(find.text('Download PDF'));
      await tester.pump();

      expect(
        find.text('Invoice PDF download is not available yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive layout', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow at ${width}px width', (tester) async {
        await _pumpInvoiceDetailsScreen(tester, width: width);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Can scroll down to the Payment Method section', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester, width: 320);

      await tester.scrollUntilVisible(
        find.text('PAYMENT METHOD'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('PAYMENT METHOD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
