// Widget checks for the Fabric Orders list screen: header/intro content,
// filter bottom sheet behavior, header search, pagination, loading/error/
// empty states, narrow-width overflow safety, and pull-to-refresh.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/fabric_order_filter.dart';
import 'package:anc_fabrics/models/paginated_fabric_orders.dart';
import 'package:anc_fabrics/screens/order_detail_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/services/mock_orders_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

/// Every Orders query (initial load, filter/search/pagination change,
/// retry) goes through the mock service's simulated 600ms network delay.
/// `pumpAndSettle` alone won't wait for that bare `Future.delayed` since
/// it isn't tied to a scheduled frame, so any interaction that triggers a
/// fetch needs this explicit pump afterwards.
Future<void> _settleFetch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

Future<void> _pumpOrdersScreen(
  WidgetTester tester, {
  double width = 390,
  MockOrdersService? ordersService,
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
      home: OrdersScreen(ordersService: ordersService),
    ),
  );
  // The translation delegate loads its JSON asset asynchronously — flush
  // that first so OrdersScreen (and its initState fetch) actually mounts
  // before _settleFetch starts counting down the mock service's delay.
  await tester.pump();
  await _settleFetch(tester);
}

Future<void> _openFilterSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('orders-open-filter-button')));
  await tester.pumpAndSettle();
}

/// The pagination controls render below the order list, past the fold of
/// the 390x800 test viewport. Flutter's default finders skip offstage
/// (scrolled-out-of-view) widgets, so pagination controls need the list
/// scrolled all the way down before they can be found/tapped, and order
/// items need it scrolled back to the top before they can be found/
/// asserted absent (an "absent" check against an offstage item would pass
/// trivially without actually proving anything).
Future<void> _scrollToPaginationControls(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
  await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
  await tester.pumpAndSettle();
}

/// Fake service that always fails — used to drive the error/retry state
/// without touching real mock data.
class _ThrowingOrdersService extends MockOrdersService {
  int callCount = 0;

  @override
  Future<PaginatedFabricOrders> fetchOrders(FabricOrderFilter filter) async {
    callCount++;
    throw Exception('mock network failure');
  }
}

/// Fake service that fails on exactly its 2nd call (simulating an error on
/// e.g. a filter/search change after a successful initial load) and
/// succeeds on every other call by delegating to the real mock filtering/
/// pagination logic — used to confirm retry preserves the current query.
class _FailsOnSecondCallOrdersService extends MockOrdersService {
  int callCount = 0;

  @override
  Future<PaginatedFabricOrders> fetchOrders(FabricOrderFilter filter) async {
    callCount++;
    if (callCount == 2) throw Exception('mock network failure');
    return super.fetchOrders(filter);
  }
}

void main() {
  testWidgets('Orders screen renders header, page intro, and orders', (
    tester,
  ) async {
    await _pumpOrdersScreen(tester);

    expect(find.text('Indigo Loom'), findsOneWidget);
    expect(find.text('Client Portal'), findsOneWidget);
    expect(find.text('GLOBAL LOGISTICS'), findsOneWidget);
    expect(find.text('Fabric Orders'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('ORD-8829'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('orders-open-filter-button')),
      findsOneWidget,
    );
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('Orders screen has no overflow at ${width}px width', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester, width: width);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Pull-to-refresh reloads orders without errors', (tester) async {
    await _pumpOrdersScreen(tester);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await _settleFetch(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('ORD-8829'), findsOneWidget);
  });

  group('Filter bottom sheet', () {
    testWidgets('Opens from the Orders filter button', (tester) async {
      await _pumpOrdersScreen(tester);

      await _openFilterSheet(tester);

      expect(find.text('Filter Orders'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Date Range'), findsOneWidget);
      expect(find.text('Fabric Type'), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-sheet-apply')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-sheet-reset')), findsOneWidget);
    });

    testWidgets(
      'Filtering by Delivered status shows Delivered orders and hides others',
      (tester) async {
        await _pumpOrdersScreen(tester);

        expect(find.text('ORD-8829'), findsOneWidget); // Delivered
        expect(find.text('ORD-8830'), findsOneWidget); // Shipped
        expect(find.text('ORD-8831'), findsOneWidget); // Processing

        await _openFilterSheet(tester);
        await tester.tap(
          find.byKey(const ValueKey('filter-sheet-status-delivered')),
        );
        await tester.tap(find.byKey(const ValueKey('filter-sheet-apply')));
        await _settleFetch(tester);

        expect(find.text('ORD-8829'), findsOneWidget); // Delivered
        expect(find.text('ORD-8830'), findsNothing); // Shipped
        expect(find.text('ORD-8831'), findsNothing); // Processing
        expect(
          find.byKey(const ValueKey('active-filter-status')),
          findsOneWidget,
        );
      },
    );

    testWidgets('Reset restores all mock orders', (tester) async {
      await _pumpOrdersScreen(tester);

      await _openFilterSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('filter-sheet-status-shipped')),
      );
      await tester.tap(find.byKey(const ValueKey('filter-sheet-apply')));
      await _settleFetch(tester);
      expect(find.text('ORD-8829'), findsNothing);

      await _openFilterSheet(tester);
      await tester.tap(find.byKey(const ValueKey('filter-sheet-reset')));
      await _settleFetch(tester);

      expect(find.text('ORD-8829'), findsOneWidget);
      expect(find.text('ORD-8830'), findsOneWidget);
      expect(find.text('ORD-8831'), findsOneWidget);
      expect(find.byKey(const ValueKey('active-filter-status')), findsNothing);
    });

    testWidgets('Empty state appears when filters produce no matches', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);

      // Shipped status + Silk fabric type: no mock order matches both
      // (Silk is exclusive to the fixed, always-Delivered #ORD-9102).
      await _openFilterSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('filter-sheet-status-shipped')),
      );
      await tester.tap(
        find.byKey(const ValueKey('filter-sheet-fabric-type-Silk')),
      );
      await tester.tap(find.byKey(const ValueKey('filter-sheet-apply')));
      await _settleFetch(tester);

      expect(
        find.text('No orders match the selected filters.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('orders-empty-reset-filters')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('orders-empty-reset-filters')),
      );
      await _settleFetch(tester);

      expect(find.text('ORD-8829'), findsOneWidget);
    });

    testWidgets('Fabric type filter section exists and its source carries the '
        'backend clarification TODO', (tester) async {
      await _pumpOrdersScreen(tester);
      await _openFilterSheet(tester);

      expect(find.text('Fabric Type'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('filter-sheet-fabric-type-All')),
        findsOneWidget,
      );

      // Normalize line-wrapped comments (`// ` prefixes + newlines) into a
      // single string so this doesn't depend on exact source formatting.
      final source = File('lib/widgets/order_filter_sheet.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'//\s*'), '')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
        source.contains(
          'TODO: Confirm the official fabric type/category values with '
          'the backend/API team before connecting live data.',
        ),
        isTrue,
      );
    });
  });

  group('Header search', () {
    testWidgets('Tapping the search icon opens the search field', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('orders-search-field')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('orders-search-cancel')),
        findsOneWidget,
      );
    });

    testWidgets('Searching by order ID filters the list', (tester) async {
      await _pumpOrdersScreen(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        '8829',
      );
      await _settleFetch(tester);

      expect(find.text('ORD-8829'), findsOneWidget);
      expect(find.text('ORD-8830'), findsNothing);
      expect(find.text('ORD-8831'), findsNothing);
    });

    testWidgets('Searching by fabric tag filters the list', (tester) async {
      await _pumpOrdersScreen(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        'cotton',
      );
      await _settleFetch(tester);

      expect(find.text('ORD-8829'), findsOneWidget); // Premium Cotton Twill
      expect(find.text('ORD-8830'), findsNothing);
      expect(find.text('ORD-8831'), findsNothing);
    });

    testWidgets('Clearing search restores the list', (tester) async {
      await _pumpOrdersScreen(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        '8829',
      );
      await _settleFetch(tester);
      expect(find.text('ORD-8830'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('orders-search-clear')));
      await _settleFetch(tester);

      expect(find.text('ORD-8829'), findsOneWidget);
      expect(find.text('ORD-8830'), findsOneWidget);
      expect(find.text('ORD-8831'), findsOneWidget);
    });

    testWidgets('Cancel closes search and clears search text', (tester) async {
      await _pumpOrdersScreen(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        '8829',
      );
      await _settleFetch(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-cancel')));
      await _settleFetch(tester);

      expect(find.byKey(const ValueKey('orders-search-field')), findsNothing);
      expect(find.text('Indigo Loom'), findsOneWidget);
      expect(find.text('Client Portal'), findsOneWidget);
      expect(find.text('ORD-8830'), findsOneWidget);
    });

    testWidgets('Search works together with an active status filter', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);

      await _openFilterSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('filter-sheet-status-delivered')),
      );
      await tester.tap(find.byKey(const ValueKey('filter-sheet-apply')));
      await _settleFetch(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        'cotton',
      );
      await _settleFetch(tester);

      // Delivered + "cotton" -> #ORD-8829 matches (and generated Cotton
      // orders, which are always Delivered too).
      expect(find.text('ORD-8829'), findsOneWidget);

      // Wool is always Shipped in both fixed and generated data, so it
      // never matches a Delivered-status query.
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        'wool',
      );
      await _settleFetch(tester);

      expect(
        find.text('No orders match the selected filters.'),
        findsOneWidget,
      );
    });

    testWidgets('No layout overflow when searching at a narrow width', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester, width: 320);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        'Premium Cotton Twill fabric order search text',
      );
      await _settleFetch(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('Pagination', () {
    testWidgets('Shows a "Showing X of Y orders" counter', (tester) async {
      await _pumpOrdersScreen(tester);
      await _scrollToPaginationControls(tester);

      expect(find.text('Showing 10 of 248 orders'), findsOneWidget);
    });

    testWidgets('Previous button is disabled on the first page', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);
      await _scrollToPaginationControls(tester);

      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('orders-page-previous')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Page 1 of 25'), findsOneWidget);
    });

    testWidgets('Next button moves to the next page and updates orders', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);
      await _scrollToPaginationControls(tester);

      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await _settleFetch(tester);

      await _scrollToPaginationControls(tester);
      expect(find.text('Page 2 of 25'), findsOneWidget);

      await _scrollToTop(tester);
      expect(find.text('ORD-9205'), findsOneWidget);
      expect(find.text('ORD-8829'), findsNothing);
    });

    testWidgets('Previous button moves back to the previous page', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);
      await _scrollToPaginationControls(tester);

      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await _settleFetch(tester);
      await _scrollToPaginationControls(tester);
      expect(find.text('Page 2 of 25'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orders-page-previous')));
      await _settleFetch(tester);

      await _scrollToPaginationControls(tester);
      expect(find.text('Page 1 of 25'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('orders-page-previous')),
      );
      expect(button.onPressed, isNull);

      await _scrollToTop(tester);
      expect(find.text('ORD-8829'), findsOneWidget);
    });

    testWidgets('Applying a filter resets pagination to page 1', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);
      await _scrollToPaginationControls(tester);

      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await _settleFetch(tester);
      await _scrollToPaginationControls(tester);
      expect(find.text('Page 2 of 25'), findsOneWidget);

      // The filter button lives in the scrollable body above the list, so
      // it needs to be scrolled back onstage before it can be tapped.
      await _scrollToTop(tester);
      await _openFilterSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('filter-sheet-status-delivered')),
      );
      await tester.tap(find.byKey(const ValueKey('filter-sheet-apply')));
      await _settleFetch(tester);
      await _scrollToPaginationControls(tester);

      expect(find.textContaining('Page 1 of'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('orders-page-previous')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Search resets pagination to page 1', (tester) async {
      await _pumpOrdersScreen(tester);
      await _scrollToPaginationControls(tester);

      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await _settleFetch(tester);
      await _scrollToPaginationControls(tester);
      expect(find.text('Page 2 of 25'), findsOneWidget);

      // The search icon lives in the AppBar, outside the scrollable body,
      // so it's always tappable regardless of list scroll position.
      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        'cotton',
      );
      await _settleFetch(tester);
      await _scrollToPaginationControls(tester);

      expect(find.textContaining('Page 1 of'), findsOneWidget);
    });

    testWidgets('Pagination works together with active filters and search', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);

      await _openFilterSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('filter-sheet-status-delivered')),
      );
      await tester.tap(find.byKey(const ValueKey('filter-sheet-apply')));
      await _settleFetch(tester);

      await tester.tap(find.byKey(const ValueKey('orders-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('orders-search-field')),
        'cotton',
      );
      await _settleFetch(tester);

      // Delivered + "cotton" matches 42 orders total (1 fixed + 41
      // generated Cotton/Delivered orders) -> 5 pages at page size 10.
      expect(find.text('ORD-8829'), findsOneWidget);
      expect(find.text('ORD-9200'), findsOneWidget);
      await _scrollToPaginationControls(tester);
      expect(find.text('Page 1 of 5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orders-page-next')));
      await _settleFetch(tester);

      await _scrollToPaginationControls(tester);
      expect(find.text('Page 2 of 5'), findsOneWidget);

      await _scrollToTop(tester);
      expect(find.text('ORD-9254'), findsOneWidget);
      expect(find.text('ORD-8829'), findsNothing);

      await _scrollToPaginationControls(tester);
      await tester.tap(find.byKey(const ValueKey('orders-page-previous')));
      await _settleFetch(tester);
      await _scrollToPaginationControls(tester);

      expect(find.text('Page 1 of 5'), findsOneWidget);

      await _scrollToTop(tester);
      expect(find.text('ORD-8829'), findsOneWidget);
    });
  });

  group('Order Detail navigation', () {
    testWidgets('Tapping an order card opens the Order Detail screen', (
      tester,
    ) async {
      await _pumpOrdersScreen(tester);

      await tester.tap(find.text('ORD-8829'));
      await _settleFetch(tester);

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('PRICE BREAKDOWN'), findsOneWidget);
    });
  });

  group('API integration preparation / query states', () {
    testWidgets('Loading skeleton appears while fetching', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          supportedLocales: [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OrdersScreen(),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('orders-loading-skeleton')),
        findsOneWidget,
      );

      await _settleFetch(tester);
      expect(
        find.byKey(const ValueKey('orders-loading-skeleton')),
        findsNothing,
      );
    });

    testWidgets('Error/retry state appears when the service throws', (
      tester,
    ) async {
      final service = _ThrowingOrdersService();
      await _pumpOrdersScreen(tester, ordersService: service);

      expect(find.text('Unable to load orders.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(service.callCount, 1);
    });

    testWidgets('Retry re-fetches using the current query', (tester) async {
      final service = _FailsOnSecondCallOrdersService();
      await _pumpOrdersScreen(tester, ordersService: service);
      expect(find.text('ORD-8829'), findsOneWidget);

      // Applying a filter is the 2nd fetchOrders call, which this fake
      // service is set up to fail on.
      await _openFilterSheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('filter-sheet-status-delivered')),
      );
      await tester.tap(find.byKey(const ValueKey('filter-sheet-apply')));
      await _settleFetch(tester);

      expect(find.text('Unable to load orders.'), findsOneWidget);
      // Filters/search are not cleared automatically after an error.
      expect(
        find.byKey(const ValueKey('active-filter-status')),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await _settleFetch(tester);

      // Retry re-ran the same (Delivered) query that failed.
      expect(find.text('ORD-8829'), findsOneWidget); // Delivered
      expect(find.text('ORD-8830'), findsNothing); // Shipped
      expect(service.callCount, 3);
    });
  });
}
