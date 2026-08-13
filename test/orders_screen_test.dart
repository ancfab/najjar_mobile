// Widget checks for the Orders screen: live sales-order-line list, the
// order-lines counter, explicit Previous/Next pagination, loading/error/
// empty/session-expiry states, duplicate-tap prevention, and pull-to-
// refresh. Mirrors the Home screen's Current Balance/Last Payment testing
// conventions (fake injectable data source, request-generation stale-
// response guard, perpetual-spinner-safe pumping for the 401 case).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/paginated_response.dart';
import 'package:anc_fabrics/models/business_central/sales_order_line.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/order_detail_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/demo_sales_order_lines_data_source.dart';
import 'package:anc_fabrics/services/sales_order_lines_data_source.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';
import 'package:anc_fabrics/widgets/sales_order_line_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

import 'helpers/fake_sales_order_lines_data_source.dart';

/// Every sales-order-lines query (initial load, pagination, retry, refresh)
/// resolves asynchronously through the fake data source; a bare `Future`
/// microtask still needs at least one extra pump to be observed.
Future<void> _settleFetch(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _pumpOrdersScreen(
  WidgetTester tester, {
  double width = 390,
  SalesOrderLinesDataSource? salesOrderLinesSource,
  Locale locale = const Locale('en'),
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
      home: OrdersScreen(
        salesOrderLinesSource:
            salesOrderLinesSource ??
            FakeSalesOrderLinesDataSource(page: samplePage()),
      ),
    ),
  );
  await tester.pump();
  await _settleFetch(tester);
}

/// Pumps an Orders screen without ever calling `pumpAndSettle`, for
/// scenarios where the screen is left showing its indeterminate loading
/// skeleton (a swallowed `SessionExpiredException` never clears loading —
/// matching `HomeScreen`'s identical Current Balance/Last Payment
/// convention) — `pumpAndSettle` would wait on that forever.
Future<void> _pumpOrdersScreenWithoutSettling(
  WidgetTester tester,
  SalesOrderLinesDataSource salesOrderLinesSource,
) async {
  tester.view.physicalSize = const Size(390, 800);
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
      home: OrdersScreen(salesOrderLinesSource: salesOrderLinesSource),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Scrolls the sliver list all the way down so the pagination footer
/// (rendered past the fold at 390x800) is onstage and tappable, regardless
/// of how many rows are above it.
Future<void> _scrollToPaginationControls(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
  await tester.pumpAndSettle();
}

/// Resolves its first call immediately with [samplePage]'s default single
/// full page, then awaits [gate] for every subsequent call — lets a test
/// observe the screen's mid-request state (disabled controls, guarded
/// duplicate taps) for a *second* request without ever leaving the
/// screen's very first load unresolved.
class _GatedAfterFirstCallDataSource implements SalesOrderLinesDataSource {
  _GatedAfterFirstCallDataSource({required this.gate});

  final Completer<PaginatedResponse<BusinessCentralSalesOrderLine>> gate;
  int callCount = 0;

  @override
  Future<PaginatedResponse<BusinessCentralSalesOrderLine>> fetchPage({
    required int page,
    int perPage = 25,
  }) async {
    callCount++;
    if (callCount == 1) {
      return samplePage(currentPage: 1, lastPage: 10, total: 248);
    }
    return gate.future;
  }
}

void main() {
  testWidgets('Orders screen renders header, page intro, and live rows', (
    tester,
  ) async {
    await _pumpOrdersScreen(tester);

    expect(find.text('Indigo Loom'), findsOneWidget);
    expect(find.text('Client Portal'), findsOneWidget);
    expect(find.text('GLOBAL LOGISTICS'), findsOneWidget);
    expect(find.text('Fabric Orders'), findsOneWidget);
    expect(find.text('SO-24001'), findsOneWidget);
    expect(find.byType(SalesOrderLineCard), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('Orders screen has no overflow at ${width}px width', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester, width: width);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('The filter/search UI from the old mock-backed screen is gone', (
    tester,
  ) async {
    await _pumpOrdersScreen(tester);

    expect(
      find.byKey(const ValueKey('orders-open-filter-button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('orders-search-open')), findsNothing);
  });

  group('Live row rendering', () {
    testWidgets(
      'Each API row is a separate list item, never grouped by Document_No',
      (tester) async {
        final rows = [
          sampleSalesOrderLine(documentNo: 'SO-24001', lineNo: 10000),
          sampleSalesOrderLine(documentNo: 'SO-24001', lineNo: 20000),
        ];
        await _pumpOrdersScreen(
          tester,
          salesOrderLinesSource: FakeSalesOrderLinesDataSource(
            page: samplePage(rows: rows, total: 2),
          ),
        );

        expect(find.byType(SalesOrderLineCard), findsNWidgets(2));
        expect(find.text('Line 10000'), findsOneWidget);
        expect(find.text('Line 20000'), findsOneWidget);
        // Only one "SO-24001" document title is rendered per line, not
        // collapsed into a single grouped row.
        expect(find.text('SO-24001'), findsNWidgets(2));
      },
    );

    testWidgets(
      'Maps only the fields the API contract documents (no status/date/'
      'fabric type/currency ever shown)',
      (tester) async {
        await _pumpOrdersScreen(
          tester,
          salesOrderLinesSource: FakeSalesOrderLinesDataSource(
            page: samplePage(
              rows: [
                sampleSalesOrderLine(
                  documentNo: 'SO-24001',
                  lineNo: 10000,
                  itemNo: '880107',
                  description: 'Test Fabric Item',
                  quantity: 12,
                  unitPrice: 15,
                  amount: 180,
                ),
              ],
              total: 1,
            ),
          ),
        );

        expect(find.text('SO-24001'), findsOneWidget);
        expect(find.text('Test Fabric Item'), findsOneWidget);
        expect(find.text('Item 880107'), findsOneWidget);
        expect(find.text('12.00 x 15.00'), findsOneWidget);
        expect(find.text('180.00'), findsOneWidget);
      },
    );
  });

  group('Navigation to Order Detail', () {
    testWidgets('tapping a row opens Order Detail for that row\'s '
        'Document_No, never Line_No', (tester) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(
            rows: [sampleSalesOrderLine(documentNo: 'SO-24001', lineNo: 20000)],
            total: 1,
          ),
        ),
      );

      await tester.tap(find.byType(SalesOrderLineCard));
      // Navigator.push needs two pumps: one to register the new route on
      // the Overlay, one more to actually build its page content — a single
      // pump leaves OrderDetailScreen not yet present in the tree.
      await tester.pump();
      await tester.pump();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      final screen = tester.widget<OrderDetailScreen>(
        find.byType(OrderDetailScreen),
      );
      expect(screen.documentNo, 'SO-24001');
    });

    testWidgets('rows sharing the same Document_No open the same Order '
        'Detail screen', (tester) async {
      final rows = [
        sampleSalesOrderLine(documentNo: 'SO-24001', lineNo: 10000),
        sampleSalesOrderLine(documentNo: 'SO-24001', lineNo: 20000),
      ];
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(rows: rows, total: 2),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('SO-24001 20000')));
      await tester.pump();
      await tester.pump();

      final screen = tester.widget<OrderDetailScreen>(
        find.byType(OrderDetailScreen),
      );
      expect(screen.documentNo, 'SO-24001');
    });

    testWidgets('a rapid double-tap opens only one Order Detail screen', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(
            rows: [sampleSalesOrderLine(documentNo: 'SO-24001')],
            total: 1,
          ),
        ),
      );

      final card = find.byType(SalesOrderLineCard);
      await tester.tap(card);
      // The first tap's push may already have started animating a new route
      // over this position, so the second tap is allowed to miss — the
      // assertion below is what actually proves the duplicate-tap guard
      // worked, not whether this second tap landed.
      await tester.tap(card, warnIfMissed: false);
      await tester.pump();
      await tester.pump();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
    });
  });

  group('Order-lines counter', () {
    testWidgets('Uses the backend from/to/total fields, wording "order '
        'lines"', (tester) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(currentPage: 1, lastPage: 10, total: 248),
        ),
      );
      await _scrollToPaginationControls(tester);

      expect(find.text('Showing 1-1 of 248 order lines'), findsOneWidget);
      expect(find.textContaining('orders'), findsNothing);
    });

    testWidgets('A final partial page shows its own from/to range', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(
            rows: List.generate(
              23,
              (i) => sampleSalesOrderLine(lineNo: (i + 1) * 10000),
            ),
            currentPage: 10,
            lastPage: 10,
            perPage: 25,
            total: 248,
          ),
        ),
      );
      await _scrollToPaginationControls(tester);

      expect(find.text('Showing 226-248 of 248 order lines'), findsOneWidget);
    });

    testWidgets('Is never derived from current_page * per_page', (
      tester,
    ) async {
      // A deliberately "wrong" from/to relative to what current_page*per_page
      // would produce, proving the screen trusts the backend's own from/to
      // rather than recomputing them.
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: PaginatedResponse<BusinessCentralSalesOrderLine>(
            currentPage: 3,
            data: [sampleSalesOrderLine()],
            firstPageUrl: 'https://api.ancfab.com/x?page=1',
            from: 9001,
            lastPage: 10,
            lastPageUrl: 'https://api.ancfab.com/x?page=10',
            nextPageUrl: 'https://api.ancfab.com/x?page=4',
            path: 'https://api.ancfab.com/x',
            perPage: 25,
            prevPageUrl: 'https://api.ancfab.com/x?page=2',
            to: 9001,
            total: 248,
          ),
        ),
      );
      await _scrollToPaginationControls(tester);

      expect(find.text('Showing 9001-9001 of 248 order lines'), findsOneWidget);
    });
  });

  group('Previous/Next pagination', () {
    testWidgets('Previous is disabled on the first page', (tester) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(currentPage: 1, lastPage: 10, total: 248),
        ),
      );
      await _scrollToPaginationControls(tester);

      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('orders-page-previous')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Page 1 of 10'), findsOneWidget);
    });

    testWidgets('Next requests current_page + 1', (tester) async {
      final source = FakeSalesOrderLinesDataSource(
        pageBuilder: (page) => samplePage(
          rows: [sampleSalesOrderLine(documentNo: 'SO-PAGE-$page')],
          currentPage: page,
          lastPage: 10,
          total: 248,
        ),
      );
      await _pumpOrdersScreen(tester, salesOrderLinesSource: source);
      await _scrollToPaginationControls(tester);

      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await _settleFetch(tester);

      expect(source.requestedPages, [1, 2]);
      await _scrollToPaginationControls(tester);
      expect(find.text('Page 2 of 10'), findsOneWidget);
      await _scrollToTop(tester);
      expect(find.text('SO-PAGE-2'), findsOneWidget);
      expect(find.text('SO-PAGE-1'), findsNothing);
    });

    testWidgets('Previous requests current_page - 1 and preserves per_page', (
      tester,
    ) async {
      final perPageSeen = <int>[];
      final source = FakeSalesOrderLinesDataSource(
        pageBuilder: (page) {
          perPageSeen.add(25);
          return samplePage(
            rows: [sampleSalesOrderLine(documentNo: 'SO-PAGE-$page')],
            currentPage: page,
            lastPage: 10,
            perPage: 25,
            total: 248,
          );
        },
      );
      await _pumpOrdersScreen(tester, salesOrderLinesSource: source);
      await _scrollToPaginationControls(tester);
      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await _settleFetch(tester);
      await _scrollToPaginationControls(tester);

      await tester.tap(find.byKey(const ValueKey('orders-page-previous')));
      await _settleFetch(tester);

      expect(source.requestedPages, [1, 2, 1]);
      await _scrollToPaginationControls(tester);
      expect(find.text('Page 1 of 10'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('orders-page-previous')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next is disabled when current_page == last_page', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(currentPage: 10, lastPage: 10, total: 248),
        ),
      );
      await _scrollToPaginationControls(tester);

      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('orders-page-next')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'Next is disabled when next_page_url is null even if current_page < '
      'last_page',
      (tester) async {
        await _pumpOrdersScreen(
          tester,
          salesOrderLinesSource: FakeSalesOrderLinesDataSource(
            page: PaginatedResponse<BusinessCentralSalesOrderLine>(
              currentPage: 3,
              data: [sampleSalesOrderLine()],
              firstPageUrl: 'https://api.ancfab.com/x?page=1',
              from: 51,
              lastPage: 10,
              lastPageUrl: 'https://api.ancfab.com/x?page=10',
              nextPageUrl: null,
              path: 'https://api.ancfab.com/x',
              perPage: 25,
              prevPageUrl: 'https://api.ancfab.com/x?page=2',
              to: 51,
              total: 248,
            ),
          ),
        );
        await _scrollToPaginationControls(tester);

        final button = tester.widget<TextButton>(
          find.byKey(const ValueKey('orders-page-next')),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      'Pagination controls are replaced by the loading skeleton while a '
      'page request is in flight — never left tappable mid-request',
      (tester) async {
        final gate =
            Completer<PaginatedResponse<BusinessCentralSalesOrderLine>>();
        final source = _GatedAfterFirstCallDataSource(gate: gate);
        await _pumpOrdersScreen(tester, salesOrderLinesSource: source);
        await _scrollToPaginationControls(tester);

        await tester.tap(find.byKey(const ValueKey('orders-page-next')));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('orders-loading-skeleton')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('orders-page-previous')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('orders-page-next')), findsNothing);
        expect(source.callCount, 2);

        gate.complete(
          samplePage(
            rows: [sampleSalesOrderLine(documentNo: 'SO-PAGE-2')],
            currentPage: 2,
            lastPage: 10,
            total: 248,
          ),
        );
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets('Duplicate taps do not issue duplicate requests', (
      tester,
    ) async {
      final gate =
          Completer<PaginatedResponse<BusinessCentralSalesOrderLine>>();
      final source = _GatedAfterFirstCallDataSource(gate: gate);
      await _pumpOrdersScreen(tester, salesOrderLinesSource: source);
      await _scrollToPaginationControls(tester);

      // Two rapid taps before any pump lets the first request's setState
      // (which flips the loading guard) run: the second tap must see the
      // button already disabled/guarded and never fire a second request.
      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await tester.tap(
        find.byKey(const ValueKey('orders-page-next')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(source.callCount, 2); // 1 initial load + 1 Next, never 2 Nexts

      gate.complete(
        samplePage(
          rows: [sampleSalesOrderLine(documentNo: 'SO-PAGE-2')],
          currentPage: 2,
          lastPage: 10,
          total: 248,
        ),
      );
      await tester.pump();
      await tester.pump();
    });
  });

  group('Loading, error, empty, and session-expiry states', () {
    testWidgets('Loading skeleton appears while fetching', (tester) async {
      final gate =
          Completer<PaginatedResponse<BusinessCentralSalesOrderLine>>();
      await _pumpOrdersScreenWithoutSettling(
        tester,
        FakeSalesOrderLinesDataSource(pendingFuture: gate.future),
      );

      expect(
        find.byKey(const ValueKey('orders-loading-skeleton')),
        findsOneWidget,
      );
      expect(find.byType(SalesOrderLineCard), findsNothing);

      gate.complete(samplePage());
      await tester.pump();
      await tester.pump();
    });

    testWidgets('Empty response shows a localized no-order-lines state', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(rows: const [], total: 0),
        ),
      );

      expect(find.byKey(const ValueKey('orders-empty-state')), findsOneWidget);
      expect(find.text('No order lines yet.'), findsOneWidget);
      expect(find.byType(SalesOrderLineCard), findsNothing);
    });

    testWidgets('HTTP 401 (SessionExpiredException) shows no local error '
        'card', (tester) async {
      await _pumpOrdersScreenWithoutSettling(
        tester,
        FakeSalesOrderLinesDataSource(error: const SessionExpiredException()),
      );

      expect(find.byKey(const ValueKey('orders-error-state')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HTTP 502 shows a retryable upstream error', (tester) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('orders-error-state')), findsOneWidget);
      expect(find.text('Unable to load orders.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('HTTP 503 shows a distinct temporarily-unavailable error', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralTemporarilyUnavailable(),
          ),
        ),
      );

      expect(find.text('Temporarily unavailable.'), findsOneWidget);
    });

    testWidgets('HTTP 422 (invalid pagination) fails safely without looping', (
      tester,
    ) async {
      final source = FakeSalesOrderLinesDataSource(
        error: const BusinessCentralFailureException(
          BusinessCentralRequestDefect('Invalid page.'),
        ),
      );
      await _pumpOrdersScreen(tester, salesOrderLinesSource: source);

      expect(find.byKey(const ValueKey('orders-error-state')), findsOneWidget);
      // No automatic retry loop: exactly the one initial request fired.
      expect(source.callCount, 1);
    });

    testWidgets('A network failure shows a retryable error', (tester) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralNetworkFailure(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('orders-error-state')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
      'A malformed response fails safely with the generic error copy',
      (tester) async {
        await _pumpOrdersScreen(
          tester,
          salesOrderLinesSource: FakeSalesOrderLinesDataSource(
            error: const BusinessCentralFailureException(
              BusinessCentralProtocolFailure(),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('orders-error-state')),
          findsOneWidget,
        );
        expect(find.text('Unable to load orders.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('No mock rows are ever shown after a live failure', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        ),
      );

      expect(find.byType(SalesOrderLineCard), findsNothing);
      expect(find.text('ORD-8829'), findsNothing);
    });

    testWidgets(
      'Retry reloads the intended (current) page, not always page 1',
      (tester) async {
        var shouldFail = false;
        final source = FakeSalesOrderLinesDataSource(
          pageBuilder: (page) {
            if (page == 2 && shouldFail) {
              shouldFail = false;
              throw const BusinessCentralFailureException(
                BusinessCentralUpstreamFailure(),
              );
            }
            return samplePage(
              rows: [sampleSalesOrderLine(documentNo: 'SO-PAGE-$page')],
              currentPage: page,
              lastPage: 10,
              total: 248,
            );
          },
        );
        await _pumpOrdersScreen(tester, salesOrderLinesSource: source);
        await _scrollToPaginationControls(tester);

        shouldFail = true;
        await tester.tap(find.byKey(const ValueKey('orders-page-next')));
        await _settleFetch(tester);

        expect(
          find.byKey(const ValueKey('orders-error-state')),
          findsOneWidget,
        );

        await tester.tap(find.text('Retry'));
        await _settleFetch(tester);

        expect(find.byKey(const ValueKey('orders-error-state')), findsNothing);
        expect(find.text('SO-PAGE-2'), findsOneWidget);
        expect(source.requestedPages, [1, 2, 2]);
      },
    );
  });

  testWidgets('Pull-to-refresh reloads the current page without errors', (
    tester,
  ) async {
    final source = FakeSalesOrderLinesDataSource(page: samplePage());
    await _pumpOrdersScreen(tester, salesOrderLinesSource: source);
    expect(source.callCount, 1);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await _settleFetch(tester);

    expect(tester.takeException(), isNull);
    expect(source.callCount, 2);
    expect(source.requestedPages, [1, 1]);
    expect(find.byType(SalesOrderLineCard), findsOneWidget);
  });

  group('Localization and RTL', () {
    testWidgets('Arabic counter wording says order lines, not orders', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        locale: const Locale('ar'),
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(currentPage: 1, lastPage: 10, total: 248),
        ),
      );
      await _scrollToPaginationControls(tester);

      expect(find.text('عرض 1-1 من أصل 248 من بنود الطلبات'), findsOneWidget);
      final context = tester.element(find.byType(OrdersScreen));
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('French counter wording says lignes de commande', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        locale: const Locale('fr'),
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(currentPage: 1, lastPage: 10, total: 248),
        ),
      );
      await _scrollToPaginationControls(tester);

      expect(
        find.text('Affichage de 1 à 1 sur 248 lignes de commande'),
        findsOneWidget,
      );
    });

    testWidgets('No overflow in Arabic RTL at a narrow width', (tester) async {
      await _pumpOrdersScreen(tester, width: 320, locale: const Locale('ar'));
      expect(tester.takeException(), isNull);
    });
  });

  group('Bottom navigation', () {
    testWidgets('Shows the Home, Orders, Support, and Profile tabs', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Reuses CustomBottomNav with Orders selected', (tester) async {
      await _pumpOrdersScreen(tester);

      expect(find.byType(CustomBottomNav), findsOneWidget);
      expect(find.byType(CustomBottomNavItem), findsNWidgets(4));

      final bottomNav = tester.widget<CustomBottomNav>(
        find.byType(CustomBottomNav),
      );
      expect(bottomNav.currentIndex, 1);
    });

    testWidgets(
      'Selecting the already-selected Orders tab does not push a new route',
      (tester) async {
        await _pumpOrdersScreen(tester);

        await tester.tap(find.text('Orders'));
        await tester.pumpAndSettle();

        expect(find.byType(OrdersScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Selecting Home is safe when there is no screen to pop back to',
      (tester) async {
        await _pumpOrdersScreen(tester);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(OrdersScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Selecting Support and Profile pushes each screen', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);

      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      expect(find.byType(SupportScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets(
      'Hopping between tabs repeatedly never leaves duplicate screens on '
      'the stack',
      (tester) async {
        await _pumpOrdersScreen(tester);

        await tester.tap(find.text('Support'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Orders'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Support'));
        await tester.pumpAndSettle();

        expect(find.byType(SupportScreen), findsOneWidget);
        expect(find.byType(OrdersScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Order Detail (a nested screen) does not show the footer', (
      tester,
    ) async {
      await _pumpOrdersScreen(
        tester,
        salesOrderLinesSource: FakeSalesOrderLinesDataSource(
          page: samplePage(
            rows: [sampleSalesOrderLine(documentNo: 'SO-24001')],
            total: 1,
          ),
        ),
      );

      await tester.tap(find.byType(SalesOrderLineCard));
      await tester.pump();
      await tester.pump();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(OrderDetailScreen),
          matching: find.byType(CustomBottomNav),
        ),
        findsNothing,
      );
    });
  });

  group('Orders demo mode', () {
    // TEMPORARY CLIENT DEMO MODE: covers
    // resolveDefaultSalesOrderLinesDataSource (the pure resolver
    // OrdersScreen falls back to when no salesOrderLinesSource is injected)
    // for both DemoConfig.useDemoOrders branches, regardless of the flag's
    // current compiled-in value.
    test('useDemo: true resolves to DemoSalesOrderLinesDataSource, never the '
        'live sales-orders integration', () {
      final source = resolveDefaultSalesOrderLinesDataSource(useDemo: true);
      expect(source, isA<DemoSalesOrderLinesDataSource>());
    });

    test('useDemo: false resolves to LiveSalesOrderLinesDataSource, leaving '
        'the live Orders integration fully reachable', () {
      final source = resolveDefaultSalesOrderLinesDataSource(useDemo: false);
      expect(source, isA<LiveSalesOrderLinesDataSource>());
    });

    testWidgets(
      'With DemoConfig.useDemoOrders false, OrdersScreen resolves its '
      'default SalesOrderLinesDataSource to Live — so widget tests must '
      'always inject a salesOrderLinesSource to avoid real HTTP/secure '
      'storage, and whatever that injected source returns is what the list '
      'shows (never DemoSalesOrderLinesDataSource.mockLines)',
      (tester) async {
        // Distinct from DemoSalesOrderLinesDataSource.mockLines on purpose:
        // if OrdersScreen ever silently fell back to the demo source instead
        // of the injected one, this assertion would catch it.
        final liveStyleLine = sampleSalesOrderLine(
          documentNo: 'SO-90001',
          description: 'Live Integration Sample Fabric',
        );

        await _pumpOrdersScreen(
          tester,
          salesOrderLinesSource: FakeSalesOrderLinesDataSource(
            page: samplePage(rows: [liveStyleLine]),
          ),
        );

        expect(find.text('Live Integration Sample Fabric'), findsOneWidget);
        expect(find.text('Premium Cotton Twill - Ivory White'), findsNothing);
      },
    );
  });
}
