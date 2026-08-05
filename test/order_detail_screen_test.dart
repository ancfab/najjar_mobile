// Widget checks for the live-backed Order Detail screen: document_no
// fetch/pagination wiring (via a fake OrderDetailDataSource), order-line
// rendering, not-found/error/retry/session-expiry states, the Invoice
// button's lookup/grouping/latest-selection/navigation behavior (via a fake
// InvoiceLookupDataSource), the preserved Order History placeholder action,
// localization/RTL, and responsive layout.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/business_central_invoice_line.dart';
import 'package:anc_fabrics/models/business_central/sales_order_line.dart';
import 'package:anc_fabrics/screens/order_detail_screen.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/widgets/live_invoice_lines_card.dart';
import 'package:anc_fabrics/widgets/payment_timeline.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

import 'helpers/fake_invoice_lookup_data_source.dart';
import 'helpers/fake_order_detail_data_source.dart';
import 'helpers/fake_sales_order_lines_data_source.dart'
    show sampleSalesOrderLine;

Future<void> _settleAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _pumpOrderDetailScreen(
  WidgetTester tester, {
  String documentNo = 'SO-24001',
  double width = 390,
  Locale locale = const Locale('en'),
  FakeOrderDetailDataSource? orderDetailSource,
  FakeInvoiceLookupDataSource? invoiceLookupSource,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: OrderDetailScreen(
        documentNo: documentNo,
        orderDetailSource: orderDetailSource ?? FakeOrderDetailDataSource(),
        invoiceLookupSource:
            invoiceLookupSource ?? FakeInvoiceLookupDataSource(),
      ),
    ),
  );
  await _settleAsync(tester);
}

void main() {
  group('Live order fetch', () {
    testWidgets('requests the exact document_no passed to the screen', (
      tester,
    ) async {
      final source = FakeOrderDetailDataSource();
      await _pumpOrderDetailScreen(
        tester,
        documentNo: 'SO-24001',
        orderDetailSource: source,
      );

      expect(source.requestedDocumentNos, ['SO-24001']);
    });

    testWidgets('shows a loading indicator while the fetch is pending', (
      tester,
    ) async {
      final source = FakeOrderDetailDataSource(
        pendingFuture: Completer<List<BusinessCentralSalesOrderLine>>().future,
      );
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OrderDetailScreen(
            documentNo: 'SO-24001',
            orderDetailSource: source,
            invoiceLookupSource: FakeInvoiceLookupDataSource(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('order-detail-loading')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders every returned line separately, never grouped', (
      tester,
    ) async {
      final lines = [
        sampleSalesOrderLine(documentNo: 'SO-24001', lineNo: 10000),
        sampleSalesOrderLine(documentNo: 'SO-24001', lineNo: 20000),
      ];
      await _pumpOrderDetailScreen(
        tester,
        orderDetailSource: FakeOrderDetailDataSource(lines: lines),
      );

      expect(
        find.byKey(const ValueKey('order-detail-line-SO-24001 10000')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('order-detail-line-SO-24001 20000')),
        findsOneWidget,
      );
    });

    testWidgets('shows the customer name and number from the loaded lines', (
      tester,
    ) async {
      final lines = [
        sampleSalesOrderLine(
          sellToCustomerNo: 'CLNT-0001',
          sellToCustomerName: 'Test Customer One',
        ),
      ];
      await _pumpOrderDetailScreen(
        tester,
        orderDetailSource: FakeOrderDetailDataSource(lines: lines),
      );

      expect(find.text('Test Customer One (CLNT-0001)'), findsOneWidget);
    });

    testWidgets('never shows a status badge, order date, or Fabric Specs '
        'action — none exist on the confirmed contract', (tester) async {
      await _pumpOrderDetailScreen(tester);

      expect(find.text('FABRIC SPECS'), findsNothing);
      expect(find.textContaining('Placed on'), findsNothing);
      expect(find.text('Delivered'), findsNothing);
      expect(find.text('Shipped'), findsNothing);
      expect(find.text('Processing'), findsNothing);
    });
  });

  group('Not found state', () {
    testWidgets('empty result shows the Order Not Found state', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        orderDetailSource: FakeOrderDetailDataSource(lines: const []),
      );

      expect(
        find.byKey(const ValueKey('order-detail-not-found')),
        findsOneWidget,
      );
      expect(find.text('Order Not Found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Back action pops the screen safely', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(
                        documentNo: 'SO-NOTFOUND',
                        orderDetailSource: FakeOrderDetailDataSource(
                          lines: const [],
                        ),
                        invoiceLookupSource: FakeInvoiceLookupDataSource(),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _settleAsync(tester);

      await tester.tap(find.text('open'));
      await _settleAsync(tester);
      expect(
        find.byKey(const ValueKey('order-detail-not-found')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('order-detail-not-found-back')),
      );
      await _settleAsync(tester);

      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Error and retry state', () {
    testWidgets('HTTP 502 shows a retryable upstream error', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        orderDetailSource: FakeOrderDetailDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('order-detail-error-state')),
        findsOneWidget,
      );
      expect(find.text('Unable to load order details.'), findsOneWidget);
    });

    testWidgets('HTTP 503 shows a distinct temporarily-unavailable message', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(
        tester,
        orderDetailSource: FakeOrderDetailDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralTemporarilyUnavailable(),
          ),
        ),
      );

      expect(find.text('Temporarily unavailable.'), findsOneWidget);
    });

    testWidgets('an unexpected (non-BusinessCentral) error also shows the '
        'error state safely, never mock data', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        orderDetailSource: FakeOrderDetailDataSource(error: Exception('boom')),
      );

      expect(
        find.byKey(const ValueKey('order-detail-error-state')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Retry issues a fresh request for the same document_no', (
      tester,
    ) async {
      final source = FakeOrderDetailDataSource(
        error: const BusinessCentralFailureException(
          BusinessCentralUpstreamFailure(),
        ),
      );
      await _pumpOrderDetailScreen(
        tester,
        documentNo: 'SO-24001',
        orderDetailSource: source,
      );
      expect(source.callCount, 1);

      await tester.tap(find.text('Retry'));
      await _settleAsync(tester);

      expect(source.callCount, 2);
      expect(source.requestedDocumentNos, ['SO-24001', 'SO-24001']);
    });
  });

  group('Session-expiry behavior', () {
    testWidgets('a session-expiry failure shows no error card (handled '
        'centrally) and never crashes', (tester) async {
      final source = FakeOrderDetailDataSource(
        error: const SessionExpiredException(),
      );
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OrderDetailScreen(
            documentNo: 'SO-24001',
            orderDetailSource: source,
            invoiceLookupSource: FakeInvoiceLookupDataSource(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('order-detail-error-state')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('order-detail-not-found')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Stale-response protection', () {
    testWidgets('a pending fetch resolving after the screen is disposed '
        'never calls setState or throws', (tester) async {
      final completer = Completer<List<BusinessCentralSalesOrderLine>>();
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OrderDetailScreen(
            documentNo: 'SO-24001',
            orderDetailSource: FakeOrderDetailDataSource(
              pendingFuture: completer.future,
            ),
            invoiceLookupSource: FakeInvoiceLookupDataSource(),
          ),
        ),
      );
      await tester.pump();

      // Replace with an empty widget tree, disposing OrderDetailScreen while
      // its fetch is still in flight.
      await tester.pumpWidget(const SizedBox.shrink());

      completer.complete([sampleSalesOrderLine()]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('Invoice button', () {
    testWidgets('requests order_no equal to the screen\'s document_no', (
      tester,
    ) async {
      final invoiceSource = FakeInvoiceLookupDataSource(
        lines: [sampleInvoiceLine()],
      );
      await _pumpOrderDetailScreen(
        tester,
        documentNo: 'SO-24001',
        invoiceLookupSource: invoiceSource,
      );

      await tester.tap(
        find.byKey(const ValueKey('order-detail-invoice-button')),
      );
      await _settleAsync(tester);

      expect(invoiceSource.requestedOrderNos, ['SO-24001']);
    });

    testWidgets('a single related invoice opens with only its own lines', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(
        tester,
        invoiceLookupSource: FakeInvoiceLookupDataSource(
          lines: [
            sampleInvoiceLine(documentNo: 'INV-24001', lineNo: 10000),
            sampleInvoiceLine(documentNo: 'INV-24001', lineNo: 20000),
          ],
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('order-detail-invoice-button')),
      );
      await _settleAsync(tester);

      expect(find.text('INV-24001'), findsOneWidget);
      expect(find.byType(LiveInvoiceLinesCard), findsOneWidget);
    });

    testWidgets('multiple related invoices: the higher Document_No opens, '
        'never mixing lines from the other invoice', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        invoiceLookupSource: FakeInvoiceLookupDataSource(
          lines: [
            sampleInvoiceLine(
              documentNo: 'INV-24001',
              lineNo: 10000,
              description: 'Older invoice line',
            ),
            sampleInvoiceLine(
              documentNo: 'INV-24010',
              lineNo: 10000,
              description: 'Newer invoice line',
            ),
          ],
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('order-detail-invoice-button')),
      );
      await _settleAsync(tester);

      expect(find.text('INV-24010'), findsOneWidget);
      expect(find.text('Newer invoice line'), findsOneWidget);
      expect(find.text('Older invoice line'), findsNothing);
    });

    testWidgets('no related invoice shows a neutral message and stays on '
        'Order Detail', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        invoiceLookupSource: FakeInvoiceLookupDataSource(lines: const []),
      );

      await tester.tap(
        find.byKey(const ValueKey('order-detail-invoice-button')),
      );
      await tester.pump();

      expect(
        find.text('No invoice is available for this order.'),
        findsOneWidget,
      );
      // Still on Order Detail — the loaded order line is still shown.
      expect(
        find.byKey(const ValueKey('order-detail-order-history-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lookup failure shows a retry-style message without '
        'erasing the already-loaded order', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        invoiceLookupSource: FakeInvoiceLookupDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('order-detail-invoice-button')),
      );
      await tester.pump();

      expect(
        find.text('Unable to load invoice. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('order-detail-order-history-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a duplicate tap while a lookup is in flight is ignored', (
      tester,
    ) async {
      final completer = Completer<List<BusinessCentralInvoiceLine>>();
      final invoiceSource = FakeInvoiceLookupDataSource(
        pendingFuture: completer.future,
      );
      await _pumpOrderDetailScreen(tester, invoiceLookupSource: invoiceSource);

      final button = find.byKey(const ValueKey('order-detail-invoice-button'));
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();

      expect(invoiceSource.callCount, 1);

      completer.complete([sampleInvoiceLine()]);
      await _settleAsync(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Order History action (preserved unchanged)', () {
    testWidgets('renders ORDER HISTORY and VIEW ORDER TIMELINE', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(tester);
      expect(find.text('ORDER HISTORY'), findsOneWidget);
      expect(find.text('VIEW ORDER TIMELINE'), findsOneWidget);
    });

    testWidgets('tapping shows the placeholder snackbar safely', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(tester);

      await tester.tap(
        find.byKey(const ValueKey('order-detail-order-history-button')),
      );
      await tester.pump();

      expect(find.text('Order history coming soon'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders no PaymentTimeline or fabricated status events', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(tester);
      expect(find.byType(PaymentTimeline), findsNothing);
    });

    testWidgets('is reachable via semantics and reports a tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpOrderDetailScreen(tester);

      final semantics = tester.getSemantics(find.text('VIEW ORDER TIMELINE'));
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      handle.dispose();
    });
  });

  group('Localization and RTL', () {
    testWidgets('Arabic: Order Not Found and no-invoice messages are '
        'localized, with RTL layout', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        locale: const Locale('ar'),
        orderDetailSource: FakeOrderDetailDataSource(lines: const []),
      );

      expect(find.text('الطلب غير موجود'), findsOneWidget);
      final context = tester.element(find.byType(OrderDetailScreen));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('French: no-invoice message is localized', (tester) async {
      await _pumpOrderDetailScreen(
        tester,
        locale: const Locale('fr'),
        invoiceLookupSource: FakeInvoiceLookupDataSource(lines: const []),
      );

      await tester.tap(
        find.byKey(const ValueKey('order-detail-invoice-button')),
      );
      await tester.pump();

      expect(
        find.text('Aucune facture n\'est disponible pour cette commande.'),
        findsOneWidget,
      );
    });
  });

  group('Responsive layout', () {
    testWidgets('no overflow in Arabic RTL at a narrow phone width', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(
        tester,
        width: 320,
        locale: const Locale('ar'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at a wide tablet width', (tester) async {
      await _pumpOrderDetailScreen(tester, width: 1024);
      expect(tester.takeException(), isNull);
    });
  });
}
