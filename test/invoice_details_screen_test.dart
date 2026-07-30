// Widget checks for the Invoice Details screen: title, breadcrumb, PAID
// status badge, invoice number/issued date, Print/Download PDF actions,
// Billed To/Due Date/Payment Method sections, the Payment Timeline section,
// narrow-width overflow safety, and scrolling to the Payment Method section.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/screens/invoice_details_screen.dart';
import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/services/invoice_document_actions.dart';
import 'package:anc_fabrics/services/invoice_pdf_service.dart';

import 'helpers/fake_invoice_document_actions.dart';
import 'helpers/fake_invoice_pdf_service.dart';
import 'helpers/valid_avatar_image.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

/// The mock Invoice Details fetch has a simulated 400ms network delay;
/// `pumpAndSettle` alone won't wait for that bare `Future.delayed` since it
/// isn't tied to a scheduled frame.
Future<void> _settleFetch(WidgetTester tester) async {
  // Lets the translation delegate's async asset load resolve first, so the
  // screen actually mounts (and its own fetch begins) before the
  // mock-service delay below is counted down.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<void> _pumpInvoiceDetailsScreen(
  WidgetTester tester, {
  String invoiceNumber = '#INV-8821',
  double width = 390,
  InvoicePdfService? pdfService,
  InvoiceDocumentActions? documentActions,
  CurrentUserAvatarController? avatarController,
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
      home: InvoiceDetailsScreen(
        invoiceNumber: invoiceNumber,
        pdfService: pdfService,
        documentActions: documentActions,
        avatarController: avatarController,
      ),
    ),
  );
  await _settleFetch(tester);
}

void main() {
  setUp(() {
    // CurrentUserAvatarController.setAvatarPath persists the path via
    // SharedPreferences; without a mock in place, the real plugin's
    // getInstance() call never resolves in a widget test (no platform to
    // answer it), hanging avatar-setting tests until they time out instead
    // of failing fast.
    SharedPreferences.setMockInitialValues({});
  });

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

    testWidgets(
      'Reflects a shared avatar image and keeps showing the person-icon '
      'fallback when none is set',
      (tester) async {
        final avatarController = CurrentUserAvatarController();
        await _pumpInvoiceDetailsScreen(
          tester,
          avatarController: avatarController,
        );

        final avatarFinder = find.byKey(
          const ValueKey('invoice-details-avatar'),
        );
        var circleAvatar = tester.widget<CircleAvatar>(
          find.descendant(
            of: avatarFinder,
            matching: find.byType(CircleAvatar),
          ),
        );
        expect(circleAvatar.backgroundImage, isNull);
        expect(
          find.descendant(
            of: avatarFinder,
            matching: find.byIcon(Icons.person),
          ),
          findsOneWidget,
        );

        late File tempFile;
        await tester.runAsync(() async {
          tempFile = await writeAndPrecacheAvatarFile(
            path:
                '${Directory.systemTemp.path}/invoice_details_avatar_test.png',
            bytes: validAvatarPngBytes,
            context: tester.element(find.byType(MaterialApp)),
          );
        });
        addTearDown(() async {
          if (await tempFile.exists()) await tempFile.delete();
        });

        await avatarController.setAvatarPath(tempFile.path);
        await tester.pumpAndSettle();

        circleAvatar = tester.widget<CircleAvatar>(
          find.descendant(
            of: avatarFinder,
            matching: find.byType(CircleAvatar),
          ),
        );
        expect(circleAvatar.backgroundImage, isNotNull);
      },
    );
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

  group('Logistics card', () {
    testWidgets(
      'Renders as a separate card, immediately after the Payment Timeline '
      'card, with the STATUS and EST. DELIVERY fields',
      (tester) async {
        await _pumpInvoiceDetailsScreen(tester);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('invoice-logistics-card')),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text('Logistics'), findsOneWidget);
        expect(find.text('Logistics Status'), findsNothing);
        expect(find.text('STATUS'), findsOneWidget);
        expect(find.text('In Production'), findsOneWidget);
        expect(find.text('EST. DELIVERY'), findsOneWidget);
        expect(find.text('Oct 30, 2023'), findsOneWidget);

        // The Logistics card must render below the Payment Timeline card,
        // not interleaved inside it or inside the main Invoice information
        // card.
        final paymentTimelineY = tester
            .getTopLeft(find.byKey(const ValueKey('payment-timeline-card')))
            .dy;
        final logisticsY = tester
            .getTopLeft(find.byKey(const ValueKey('invoice-logistics-card')))
            .dy;
        expect(logisticsY, greaterThan(paymentTimelineY));
      },
    );

    testWidgets('STATUS and EST. DELIVERY are separate, stacked, full-width '
        'boxes, not side by side', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('invoice-logistics-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      final statusBox = tester.getRect(
        find.byKey(const ValueKey('invoice-logistics-status-box')),
      );
      final deliveryBox = tester.getRect(
        find.byKey(const ValueKey('invoice-logistics-delivery-box')),
      );

      expect(deliveryBox.top, greaterThanOrEqualTo(statusBox.bottom));
      expect(statusBox.left, deliveryBox.left);
      expect(statusBox.width, deliveryBox.width);
    });

    testWidgets('Renders a small status dot before the status text', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('invoice-logistics-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.byKey(const ValueKey('invoice-logistics-status-dot')),
        findsOneWidget,
      );
    });

    testWidgets('The PAID status badge remains visible and unrelated to the '
        'Logistics card', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('invoice-logistics-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('Logistics'), findsOneWidget);
    });

    testWidgets('Can scroll from the header down to the Logistics card', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester, width: 320);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('invoice-logistics-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Logistics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Line-items table', () {
    testWidgets('Renders the four column headers', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('ITEM DETAILS'), findsOneWidget);
      expect(find.text('QTY'), findsOneWidget);
      expect(find.text('UNIT PRICE'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
    });

    testWidgets('Renders the first line item', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('Egyptian Cotton Sateen (600TC)'), findsOneWidget);
      expect(find.text('Midnight Blue Dye Finish, 50m Roll'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('\$850.00'), findsOneWidget);
      expect(find.text('\$10,200.00'), findsOneWidget);
      // "Rolls" is the unit for both line items.
      expect(find.text('Rolls'), findsNWidgets(2));
    });

    testWidgets('Renders the second line item', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('Brushed Twill Weave'), findsOneWidget);
      expect(
        find.text('Industrial Strength Heavy-Weight, 30m Roll'),
        findsOneWidget,
      );
      expect(find.text('5'), findsOneWidget);
      expect(find.text('\$410.00'), findsOneWidget);
      expect(find.text('\$2,050.00'), findsOneWidget);
    });

    testWidgets('Line totals are quantity times unit price, not independently '
        'hardcoded', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);

      // 12 x $850.00 and 5 x $410.00.
      expect(find.text('\$10,200.00'), findsOneWidget);
      expect(find.text('\$2,050.00'), findsOneWidget);
    });

    testWidgets('Renders Subtotal calculated from the line item totals', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('Subtotal'), findsOneWidget);
      // $10,200.00 + $2,050.00.
      expect(find.text('\$12,250.00'), findsOneWidget);
    });

    testWidgets('Renders Tax and Total Amount, where total is subtotal + tax', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);

      expect(find.text('Tax'), findsOneWidget);
      expect(find.text('\$612.50'), findsOneWidget);
      expect(find.text('Total Amount'), findsOneWidget);
      // $12,250.00 + $612.50.
      expect(find.text('\$12,862.50'), findsOneWidget);
    });
  });

  group('Payment Timeline', () {
    testWidgets(
      'Renders as a separate card, outside the main Invoice information '
      'card, below the Total Amount row',
      (tester) async {
        await _pumpInvoiceDetailsScreen(tester);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('payment-timeline-card')),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text('Payment Timeline'), findsOneWidget);
        final totalAmountY = tester.getTopLeft(find.text('Total Amount')).dy;
        final paymentTimelineY = tester
            .getTopLeft(find.byKey(const ValueKey('payment-timeline-card')))
            .dy;
        expect(paymentTimelineY, greaterThan(totalAmountY));
      },
    );

    testWidgets('Renders the heading and all three events in newest-first '
        'order', (tester) async {
      await _pumpInvoiceDetailsScreen(tester);
      await tester.scrollUntilVisible(
        find.text('Payment Timeline'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Payment Timeline'), findsOneWidget);

      expect(find.text('Payment Received'), findsOneWidget);
      expect(find.text('Oct 16, 2023 - 09:12 AM'), findsOneWidget);
      expect(find.text('Invoice Sent'), findsOneWidget);
      expect(find.text('Oct 14, 2023 - 02:45 PM'), findsOneWidget);
      expect(find.text('Invoice Generated'), findsOneWidget);
      expect(find.text('Oct 14, 2023 - 01:20 PM'), findsOneWidget);

      // Newest-first: "Payment Received" appears above "Invoice Sent",
      // which appears above "Invoice Generated".
      final paymentReceivedY = tester
          .getTopLeft(find.text('Payment Received'))
          .dy;
      final invoiceSentY = tester.getTopLeft(find.text('Invoice Sent')).dy;
      final invoiceGeneratedY = tester
          .getTopLeft(find.text('Invoice Generated'))
          .dy;
      expect(paymentReceivedY, lessThan(invoiceSentY));
      expect(invoiceSentY, lessThan(invoiceGeneratedY));
    });

    testWidgets(
      'Renders exactly three completed checkmarks and connectors only '
      'between events',
      (tester) async {
        await _pumpInvoiceDetailsScreen(tester);
        await tester.scrollUntilVisible(
          find.text('Payment Timeline'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.byIcon(Icons.check), findsNWidgets(3));
        expect(
          find.byKey(const ValueKey('payment-timeline-marker')),
          findsNWidgets(3),
        );
        // 3 events => 2 connectors (none after the last event).
        expect(
          find.byKey(const ValueKey('payment-timeline-connector')),
          findsNWidgets(2),
        );
      },
    );
  });

  group('Internal Notes', () {
    testWidgets('Renders the heading and the mock invoice note', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester);
      await tester.scrollUntilVisible(
        find.text('Internal Notes'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Internal Notes'), findsOneWidget);
      expect(
        find.textContaining('Thank you for your continued business'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Renders after the Logistics card, not between Payment Timeline and '
      'Logistics',
      (tester) async {
        await _pumpInvoiceDetailsScreen(tester);
        await tester.scrollUntilVisible(
          find.text('Internal Notes'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        final logisticsY = tester
            .getTopLeft(find.byKey(const ValueKey('invoice-logistics-card')))
            .dy;
        final notesY = tester.getTopLeft(find.text('Internal Notes')).dy;
        expect(notesY, greaterThan(logisticsY));
      },
    );
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

    testWidgets(
      'Tapping Print generates the PDF and calls printPdf with a sanitized '
      'filename',
      (tester) async {
        final pdfService = FakeInvoicePdfService();
        final documentActions = FakeInvoiceDocumentActions();
        await _pumpInvoiceDetailsScreen(
          tester,
          pdfService: pdfService,
          documentActions: documentActions,
        );

        await tester.tap(find.text('Print'));
        await tester.pumpAndSettle();

        expect(pdfService.generatedFor, hasLength(1));
        expect(pdfService.generatedFor.single.invoiceNumber, '#INV-8821');
        expect(documentActions.printCalls, hasLength(1));
        expect(
          documentActions.printCalls.single.filename,
          'invoice-INV-8821.pdf',
        );
        expect(documentActions.saveCalls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Tapping Download PDF generates the PDF and calls savePdf with a '
      'sanitized filename',
      (tester) async {
        final pdfService = FakeInvoicePdfService();
        final documentActions = FakeInvoiceDocumentActions();
        await _pumpInvoiceDetailsScreen(
          tester,
          pdfService: pdfService,
          documentActions: documentActions,
        );

        await tester.tap(find.text('Download PDF'));
        await tester.pumpAndSettle();

        expect(pdfService.generatedFor, hasLength(1));
        expect(documentActions.saveCalls, hasLength(1));
        expect(
          documentActions.saveCalls.single.filename,
          'invoice-INV-8821.pdf',
        );
        expect(documentActions.printCalls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Shows a loading spinner on Print and disables both buttons while '
      'the PDF is being prepared, then restores them',
      (tester) async {
        final pendingPrint = Completer<bool>();
        final documentActions = FakeInvoiceDocumentActions(
          pendingPrint: pendingPrint,
        );
        await _pumpInvoiceDetailsScreen(
          tester,
          documentActions: documentActions,
        );

        await tester.tap(find.text('Print'));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('invoice-action-print-loading')),
          findsOneWidget,
        );
        expect(find.text('Print'), findsNothing);
        // Download PDF is disabled too, but tapping still shouldn't crash.
        await tester.tap(find.text('Download PDF'));
        await tester.pump();
        expect(documentActions.saveCalls, isEmpty);

        pendingPrint.complete(true);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('invoice-action-print-loading')),
          findsNothing,
        );
        expect(find.text('Print'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Ignores a second Print tap while the first is still in flight',
      (tester) async {
        final pdfService = FakeInvoicePdfService();
        final pendingPrint = Completer<bool>();
        final documentActions = FakeInvoiceDocumentActions(
          pendingPrint: pendingPrint,
        );
        await _pumpInvoiceDetailsScreen(
          tester,
          pdfService: pdfService,
          documentActions: documentActions,
        );

        await tester.tap(find.text('Print'));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('invoice-action-print-button')),
        );
        await tester.pump();

        expect(pdfService.generatedFor, hasLength(1));
        expect(documentActions.printCalls, hasLength(1));

        pendingPrint.complete(true);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Shows a cancellation message when the print dialog is dismissed',
      (tester) async {
        await _pumpInvoiceDetailsScreen(
          tester,
          documentActions: FakeInvoiceDocumentActions(printResult: false),
        );

        await tester.tap(find.text('Print'));
        await tester.pumpAndSettle();

        expect(find.text('Printing was cancelled.'), findsOneWidget);
      },
    );

    testWidgets(
      'Shows a cancellation message when the save sheet is dismissed',
      (tester) async {
        await _pumpInvoiceDetailsScreen(
          tester,
          documentActions: FakeInvoiceDocumentActions(saveResult: false),
        );

        await tester.tap(find.text('Download PDF'));
        await tester.pumpAndSettle();

        expect(find.text('Download was cancelled.'), findsOneWidget);
      },
    );

    testWidgets('Shows a failure message when PDF generation throws', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(
        tester,
        pdfService: FakeInvoicePdfService(bytes: Exception('boom')),
      );

      await tester.tap(find.text('Print'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to print the invoice. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shows a failure message when the native save flow throws', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(
        tester,
        documentActions: FakeInvoiceDocumentActions(
          saveResult: Exception('boom'),
        ),
      );

      await tester.tap(find.text('Download PDF'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to prepare the invoice PDF. Please try again.'),
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

    testWidgets('Can scroll from the header down to the Payment Timeline', (
      tester,
    ) async {
      await _pumpInvoiceDetailsScreen(tester, width: 320);

      expect(find.text('Invoice Details'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('PAYMENT METHOD'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('PAYMENT METHOD'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Total Amount'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Total Amount'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Payment Timeline'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Payment Timeline'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Long item descriptions wrap without clipping on a narrow viewport',
      (tester) async {
        await _pumpInvoiceDetailsScreen(tester, width: 320);

        await tester.scrollUntilVisible(
          find.text('Industrial Strength Heavy-Weight, 30m Roll'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          find.text('Industrial Strength Heavy-Weight, 30m Roll'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
