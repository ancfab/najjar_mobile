//The test folder contains automated Flutter widget tests. We added Home screen tests to validate navigation, responsive layout, catalogue lookup states, and pull-to-refresh behavior. These tests do not affect the production app; they are only used during development to make sure future changes do not break the UI.
// Widget checks for the Home screen: narrow-width overflow safety and the
// navigation wiring for the Scan CTA and bottom tab bar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/business_central/business_central_item_search_group.dart';
import 'package:anc_fabrics/models/business_central/payment_entry.dart';
import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/scan_stock_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/current_balance_data_source.dart';
import 'package:anc_fabrics/services/current_balance_service.dart';
import 'package:anc_fabrics/services/demo_current_balance_data_source.dart';
import 'package:anc_fabrics/services/home_dashboard_service.dart';
import 'package:anc_fabrics/services/item_catalogue_search_service.dart';
import 'package:anc_fabrics/services/last_payment_data_source.dart';
import 'package:anc_fabrics/services/stock_lookup_service.dart';
import 'package:anc_fabrics/theme/app_colors.dart';
import 'package:anc_fabrics/widgets/availability_search_card.dart';
import 'package:anc_fabrics/widgets/balance_card.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';
import 'package:anc_fabrics/widgets/home_header.dart';
import 'package:anc_fabrics/widgets/last_payment_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

import 'helpers/fake_auth_session_store.dart';
import 'helpers/fake_current_balance_data_source.dart';
import 'helpers/fake_home_dashboard_service.dart';
import 'helpers/fake_item_catalogue_search_service.dart';
import 'helpers/fake_last_payment_data_source.dart';
import 'helpers/fake_stock_lookup_service.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

/// An http.Client that fails the test if it is ever called — Home screen's
/// username load only ever calls [AuthService.currentSession] (a local
/// secure-storage read), never the network, so any real HTTP attempt here
/// indicates a bug.
class _ShouldNeverBeCalledHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError(
      'AuthService must not call the ANC API from HomeScreen — only '
      'currentSession (a local secure-storage read) is used here.',
    );
  }

  @override
  void close() {}
}

/// Builds a real [AuthService] over a [FakeAuthSessionStore] seeded with
/// [session] (or left empty when `null`, simulating no persisted session) —
/// the same real-service-over-fake-transport pattern used throughout
/// edit_profile_screen_test.dart, so HomeScreen's real
/// `AuthService.currentSession` call is exercised for real rather than
/// re-implemented as a parallel fake.
AuthService _authServiceFor({AuthSession? session}) {
  final store = FakeAuthSessionStore();
  if (session != null) store.seed(session);
  return AuthService(
    apiClient: AncApiClient(httpClient: _ShouldNeverBeCalledHttpClient()),
    sessionStore: store,
  );
}

/// Builds a single-variation exact-commonItemNo match, the common fixture
/// shape for tests that only care about the eventual stock lookup, not
/// catalogue search/suggestion behavior itself — [commonItemNo] and
/// [itemNo] default to the same value so "search X" resolves straight to
/// one variation whose itemNo is also X.
ItemCatalogueExactMatch _singleVariationExactMatch(
  String commonItemNo, {
  String? itemNo,
  String? description,
}) {
  final resolvedItemNo = itemNo ?? commonItemNo;
  return ItemCatalogueExactMatch(
    commonItemNo,
    BusinessCentralItemSearchGroup(
      commonItemNo: commonItemNo,
      totalInventory: 0,
      variations: [
        BusinessCentralItemVariation(
          id: 'id-$resolvedItemNo',
          itemNo: resolvedItemNo,
          commonItemNo: commonItemNo,
          description: description,
        ),
      ],
    ),
  );
}

/// Taps a variation row's inline "Check" / "Retry" button (keyed
/// `variation-check-<itemNo>`) and settles — the interaction that runs the
/// per-variation stock lookup now that the row itself is no longer a tap
/// target.
Future<void> _tapCheck(WidgetTester tester, String itemNo) async {
  final finder = find.byKey(ValueKey('variation-check-$itemNo'));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The background colour of a resolved variation status pill — [suffix] is
/// `'available'`, `'low'`, or `'out'`.
Color? _pillColor(WidgetTester tester, String suffix) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('variation-status-$suffix')),
  );
  return (container.decoration as BoxDecoration?)?.color;
}

/// A canned [LastPaymentSummary] (negative `amount`, matching the confirmed
/// `customer_details.lastPaymentAmount` contract's sign convention), used
/// as the default Last Payment fixture so pre-existing Home screen tests
/// (that don't care about Last Payment specifically) get a fast,
/// deterministic, non-mock result instead of hitting real HTTP/secure
/// storage — which never resolves in this widget-test sandbox (see
/// AccountBalanceScreen's Quick History tests for the same issue with a
/// live data source default).
LastPaymentSummary _sampleLastPaymentSummary({
  DateTime? date,
  double amount = -200.0,
}) {
  return LastPaymentSummary(amount: amount, date: date ?? DateTime(2026, 1, 5));
}

/// A canned live [CurrentBalanceAmount], distinct from both the retired
/// `$42,850.00` mock and the confirmed USD contract example, used as the
/// default Current Balance fixture so pre-existing Home screen tests (that
/// don't care about Current Balance specifically) get a fast, deterministic,
/// non-mock result instead of hitting real HTTP/secure storage — which
/// never resolves in this widget-test sandbox (same issue documented for
/// Last Payment below).
const _sampleCurrentBalance = CurrentBalanceAmount(
  amount: 15320.75,
  currencyCode: 'AED',
);

Future<void> _pumpHomeScreen(
  WidgetTester tester,
  double width, {
  LastPaymentDataSource? lastPaymentSource,
  CurrentBalanceDataSource? currentBalanceSource,
  StockLookupService? checkAvailabilityService,
  ItemCatalogueSearchService? catalogueSearchService,
  AuthService? authService,
  HomeDashboardService? dashboardService,
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
      home: HomeScreen(
        lastPaymentSource:
            lastPaymentSource ??
            FakeLastPaymentDataSource(entry: _sampleLastPaymentSummary()),
        currentBalanceSource:
            currentBalanceSource ??
            FakeCurrentBalanceDataSource(amount: _sampleCurrentBalance),
        // Check Availability only performs a lookup on user action (unlike
        // Last Payment, it never auto-fetches on initState), so these fakes
        // are never actually invoked by tests that don't search — they
        // exist so a test that DOES search never accidentally reaches the
        // live ApiItemCatalogueSearchService/ApiStockLookupService defaults
        // (real HTTP/secure storage).
        catalogueSearchService:
            catalogueSearchService ?? FakeItemCatalogueSearchService(),
        checkAvailabilityService:
            checkAvailabilityService ?? FakeStockLookupService(),
        authService: authService ?? _authServiceFor(),
        // Defaults to a fake — the live ApiHomeDashboardService default
        // would make a real network call in this widget-test sandbox.
        dashboardService: dashboardService ?? FakeHomeDashboardService(),
      ),
    ),
  );
  await tester.pump();
  // Home screen loads dashboard data on initState; advance past the fake's
  // async resolution explicitly since pumpAndSettle won't wait for a bare
  // Timer that isn't tied to a scheduled frame.
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

/// Pumps a Home screen without ever calling `pumpAndSettle`, for scenarios
/// where the Last Payment row is left showing its indeterminate
/// [CircularProgressIndicator] (loading, or a swallowed
/// [SessionExpiredException]) — `pumpAndSettle` would wait on that
/// perpetually-animating spinner forever.
Future<void> _pumpHomeScreenWithoutSettling(
  WidgetTester tester,
  LastPaymentDataSource lastPaymentSource, {
  CurrentBalanceDataSource? currentBalanceSource,
}) async {
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
      home: HomeScreen(
        lastPaymentSource: lastPaymentSource,
        currentBalanceSource:
            currentBalanceSource ??
            FakeCurrentBalanceDataSource(amount: _sampleCurrentBalance),
        authService: _authServiceFor(),
        dashboardService: FakeHomeDashboardService(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

/// Throws a [BusinessCentralFailureException] on its first call (simulating
/// a retryable upstream failure), then succeeds on every call after —
/// lets a test prove Retry issues a brand-new live request rather than
/// replaying a cached failure.
class _FlakyLastPaymentDataSource implements LastPaymentDataSource {
  int callCount = 0;

  @override
  Future<LastPaymentSummary?> fetchLatestPayment() async {
    callCount++;
    if (callCount == 1) {
      throw const BusinessCentralFailureException(
        BusinessCentralUpstreamFailure(),
      );
    }
    return _sampleLastPaymentSummary();
  }
}

/// Throws a [BusinessCentralFailureException] on its first call (simulating
/// a retryable upstream failure), then succeeds on every call after — the
/// Current Balance counterpart to [_FlakyLastPaymentDataSource].
class _FlakyCurrentBalanceDataSource implements CurrentBalanceDataSource {
  int callCount = 0;

  @override
  Future<CurrentBalanceAmount> fetchCurrentBalance() async {
    callCount++;
    if (callCount == 1) {
      throw const BusinessCentralFailureException(
        BusinessCentralUpstreamFailure(),
      );
    }
    return _sampleCurrentBalance;
  }
}

/// Answers each successive [fetchCurrentBalance] call with the next
/// [Completer] from [_pending], in call order — lets a test control exactly
/// when each of several in-flight calls resolves, to exercise stale-response
/// protection (a slower earlier call resolving after a faster later one).
class _SequencedCurrentBalanceDataSource implements CurrentBalanceDataSource {
  _SequencedCurrentBalanceDataSource(this._pending);

  final List<Completer<CurrentBalanceAmount>> _pending;
  int callCount = 0;

  @override
  Future<CurrentBalanceAmount> fetchCurrentBalance() async {
    final completer = _pending[callCount];
    callCount++;
    return completer.future;
  }
}

/// Pumps only far enough for a pushed route's transition to finish, without
/// waiting for every animation to settle.
///
/// AccountBalanceScreen's Quick History defaults to a live
/// LedgerQuickHistoryDataSource, which in this widget-test sandbox never
/// resolves (no secure-storage platform handler is registered), leaving its
/// loading spinner animating indefinitely. These navigation tests only care
/// that the push transition completed, not that Quick History finished
/// loading, so `pumpAndSettle` (which would wait on that spinner forever)
/// is deliberately avoided here.
Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await tester.pump(); // start the push transition
  // AccountBalanceScreen's _loadSummary awaits MockAccountBalanceService's
  // two 400ms simulated delays sequentially (fetchSummary, then
  // fetchCreditUtilization) — long enough for both, plus the push
  // transition, to finish, so no dangling Timer trips
  // AutomatedTestWidgetsFlutterBinding's post-test invariant check.
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(); // let the now-covered route finish settling offstage
}

void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('Home screen has no overflow at ${width}px width', (
      tester,
    ) async {
      await _pumpHomeScreen(tester, width);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Scan Fabric Availability CTA opens the Scan Stock screen', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.tap(find.text('Scan Fabric Availability'));
    // ScanStockScreen's QR-frame corners/scan-line run a perpetually
    // repeating AnimationController, which pumpAndSettle would wait on
    // forever — pump just far enough for the push transition to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ScanStockScreen), findsOneWidget);
    expect(find.text('Scan Stock'), findsOneWidget);
    // Not asserted here: the scanning UI (QR frame/instruction), since
    // reaching it requires the real camera permission request to resolve
    // — this test doesn't inject a fake permission/scanner service (that's
    // covered in scan_stock_screen_test.dart), and no platform channel
    // handler is registered for permission_handler in this widget test.
  });

  testWidgets('Bottom tabs navigate to Orders, Support, and Profile', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.byType(OrdersScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.byType(SupportScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  group('Bottom navigation', () {
    testWidgets('Shows the bottom navigation with Home selected', (
      tester,
    ) async {
      await _pumpHomeScreen(tester, 390);

      expect(find.byType(CustomBottomNav), findsOneWidget);
      expect(find.byType(CustomBottomNavItem), findsNWidgets(4));

      final bottomNav = tester.widget<CustomBottomNav>(
        find.byType(CustomBottomNav),
      );
      expect(bottomNav.currentIndex, 0);
    });

    testWidgets(
      'Tapping the already-selected Home tab does not push a new route',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets(
    'Catalogue search shows a validation error on empty input without '
    'calling the API',
    (tester) async {
      final catalogueSearchService = FakeItemCatalogueSearchService();
      await _pumpHomeScreen(
        tester,
        390,
        catalogueSearchService: catalogueSearchService,
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();

      expect(find.text('Please enter a catalogue code.'), findsOneWidget);
      expect(catalogueSearchService.callCount, 0);
    },
  );

  testWidgets(
    'Catalogue search resolves an exact match, and selecting its only '
    'variation shows a success result',
    (tester) async {
      final gate = Completer<void>();
      final catalogueSearchService = FakeItemCatalogueSearchService()
        ..gate = gate
        ..defaultResultBuilder = (query) =>
            _singleVariationExactMatch(query, description: 'Test Fabric');
      final stockLookupService = FakeStockLookupService()
        ..defaultResultBuilder = (rawCode) => StockLookupSuccess(
          rawCode,
          scannedAt: DateTime(2026, 1, 1),
          description: 'Test Fabric',
          availabilityByLocation: const [
            StockLocationAvailability(
              locationCode: 'LOC-01',
              remainingQuantity: 150,
              unitOfMeasureCode: 'MT',
            ),
          ],
        );
      await _pumpHomeScreen(
        tester,
        390,
        catalogueSearchService: catalogueSearchService,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), 'TEST-ITEM-01');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(catalogueSearchService.calls, ['TEST-ITEM-01']);

      gate.complete();
      await tester.pumpAndSettle();

      expect(stockLookupService.calls, isEmpty, reason: 'not checked yet');
      await _tapCheck(tester, 'TEST-ITEM-01');

      expect(stockLookupService.calls, ['TEST-ITEM-01']);
      // The variation's own description is shown as the row subtitle.
      expect(find.text('Test Fabric'), findsWidgets);
      // One combined status pill — green (150 m MT, above the threshold) —
      // never a per-location breakdown and never the real quantity.
      expect(
        find.byKey(const ValueKey('variation-status-available')),
        findsOneWidget,
      );
      expect(_pillColor(tester, 'available'), AppColors.stockAvailableBg);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('LOC-01'), findsNothing);
      expect(find.textContaining('150'), findsNothing);
    },
  );

  testWidgets('Catalogue search shows a no-match state for unknown codes', (
    tester,
  ) async {
    final catalogueSearchService = FakeItemCatalogueSearchService()
      ..defaultResultBuilder = ItemCatalogueNoResults.new;
    await _pumpHomeScreen(
      tester,
      390,
      catalogueSearchService: catalogueSearchService,
    );

    await tester.enterText(find.byType(TextField), 'UNKNOWN-CODE');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    expect(find.text('No catalogue found for "UNKNOWN-CODE".'), findsOneWidget);
  });

  group('Check Availability card', () {
    /// Finds the search button's InkWell, scoped to AvailabilitySearchCard
    /// so it is never confused with any other card's tap target — stable
    /// across loading/idle states, unlike `find.byIcon(Icons.search_rounded)`
    /// which disappears once the button swaps to a spinner.
    final searchButtonFinder = find.descendant(
      of: find.byType(AvailabilitySearchCard),
      matching: find.byType(InkWell),
    );

    group('catalogue search', () {
      testWidgets('surrounding whitespace is trimmed before searching', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService();
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), '  TEST-ITEM-01  ');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(catalogueSearchService.calls, ['TEST-ITEM-01']);
      });

      testWidgets('a meaningful internal space is preserved exactly', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService();
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), '  1038 01  ');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(catalogueSearchService.calls, ['1038 01']);
      });

      testWidgets(
        'duplicate submissions are prevented while a search is active',
        (tester) async {
          final gate = Completer<void>();
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..gate = gate;
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
          );

          await tester.enterText(find.byType(TextField), 'ITEM-DUP');
          await tester.tap(searchButtonFinder);
          await tester.pump();

          expect(catalogueSearchService.callCount, 1);

          // A further tap while loading (the button now shows a spinner,
          // onTap: null) must not start a second search.
          await tester.tap(searchButtonFinder, warnIfMissed: false);
          await tester.pump();

          expect(catalogueSearchService.callCount, 1);

          gate.complete();
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'keyboard submission and the search button use the same search '
        'logic',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = _singleVariationExactMatch;
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
          );

          await tester.enterText(find.byType(TextField), 'ITEM-KB');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(catalogueSearchService.calls, ['ITEM-KB']);
          expect(
            find.byKey(const ValueKey('variation-ITEM-KB')),
            findsOneWidget,
            reason:
                'the default exact-match fixture always yields a resolved '
                'group, whichever code path triggered the search',
          );
        },
      );

      testWidgets('HTTP 401 (session expiry) shows no local error card', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = ItemCatalogueSessionExpired.new;
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-401');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(
          find.text('Something went wrong while searching. Please try again.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('HTTP 502 / a network failure shows a retryable error', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = ItemCatalogueRetryableFailure.new;
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-502');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(
          find.text('Something went wrong while searching. Please try again.'),
          findsOneWidget,
        );
      });

      testWidgets('HTTP 503 shows a distinct temporarily-unavailable error', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = ItemCatalogueTemporarilyUnavailable.new;
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-503');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Temporarily unavailable.'), findsOneWidget);
      });

      testWidgets(
        'retry after a search failure sends a new API request and no mock '
        'result is ever shown',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = ItemCatalogueRetryableFailure.new;
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
          );

          await tester.enterText(find.byType(TextField), 'ITEM-RETRY');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();

          expect(catalogueSearchService.callCount, 1);
          expect(
            find.text(
              'Something went wrong while searching. Please try again.',
            ),
            findsOneWidget,
          );

          catalogueSearchService.defaultResultBuilder =
              _singleVariationExactMatch;
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();

          expect(catalogueSearchService.callCount, 2);
          expect(
            find.byKey(const ValueKey('variation-ITEM-RETRY')),
            findsOneWidget,
          );
          expect(
            find.text(
              'Something went wrong while searching. Please try again.',
            ),
            findsNothing,
          );
        },
      );

      testWidgets(
        'starting a new search clears a previous selection and result',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = _singleVariationExactMatch;
          final stockLookupService = FakeStockLookupService()
            ..defaultResultBuilder = (rawCode) => StockLookupSuccess(
              rawCode,
              scannedAt: DateTime(2026, 1, 1),
              availabilityByLocation: const [
                StockLocationAvailability(
                  locationCode: 'LOC-01',
                  remainingQuantity: 150,
                  unitOfMeasureCode: 'MT',
                ),
              ],
            );
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
            checkAvailabilityService: stockLookupService,
          );

          await tester.enterText(find.byType(TextField), 'ITEM-A');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();
          await _tapCheck(tester, 'ITEM-A');

          expect(
            find.byKey(const ValueKey('variation-ITEM-A')),
            findsOneWidget,
          );
          expect(find.text('Available'), findsOneWidget);

          await tester.enterText(find.byType(TextField), 'ITEM-B');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();

          expect(find.byKey(const ValueKey('variation-ITEM-A')), findsNothing);
          expect(find.text('Available'), findsNothing);
          expect(
            find.byKey(const ValueKey('variation-status-available')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('variation-ITEM-B')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'an exact commonItemNo match shows only that group\'s variations, '
        'never other groups the search also returned',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = (query) => ItemCatalogueExactMatch(
              query,
              const BusinessCentralItemSearchGroup(
                commonItemNo: '1012',
                totalInventory: 2523.9,
                variations: [
                  BusinessCentralItemVariation(id: 'id-1', itemNo: '1012A01'),
                  BusinessCentralItemVariation(id: 'id-2', itemNo: '1012A02'),
                ],
              ),
            );
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
          );

          await tester.enterText(find.byType(TextField), '1012');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('variation-1012A01')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('variation-1012A02')),
            findsOneWidget,
          );
          expect(find.text('Catalogue 1012'), findsOneWidget);
          expect(find.text('Matching catalogues'), findsNothing);
        },
      );

      testWidgets('no exact commonItemNo match shows every returned group as a '
          'suggestion', (tester) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = (query) => ItemCatalogueSuggestions(query, [
            const BusinessCentralItemSearchGroup(
              commonItemNo: '1101',
              totalInventory: 40,
              variations: [
                BusinessCentralItemVariation(id: 'id-1', itemNo: '110120'),
              ],
            ),
            const BusinessCentralItemSearchGroup(
              commonItemNo: '1610',
              totalInventory: 12,
              variations: [
                BusinessCentralItemVariation(id: 'id-2', itemNo: '161012'),
              ],
            ),
          ]);
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), '1012');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Matching catalogues'), findsOneWidget);
        expect(find.text('Catalogue 1101'), findsOneWidget);
        expect(find.text('Catalogue 1610'), findsOneWidget);
        expect(find.byKey(const ValueKey('variation-110120')), findsNothing);
      });
    });

    group('variation selection and stock lookup', () {
      testWidgets('selecting a variation looks up its exact itemNo', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = (query) => ItemCatalogueExactMatch(
            query,
            const BusinessCentralItemSearchGroup(
              commonItemNo: '1012',
              totalInventory: 100,
              variations: [
                BusinessCentralItemVariation(id: 'id-1', itemNo: '1012A01'),
                BusinessCentralItemVariation(id: 'id-2', itemNo: '1012B03'),
              ],
            ),
          );
        final stockLookupService = FakeStockLookupService();
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), '1012');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        await _tapCheck(tester, '1012B03');

        expect(stockLookupService.calls, ['1012B03']);
      });

      testWidgets('tapping a visible variation row calls the catalogue search '
          'exactly once (for the original query) and the stock lookup '
          'exactly once (for the exact itemNo) — never a second catalogue '
          'search for the itemNo', (tester) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = (query) => ItemCatalogueExactMatch(
            query,
            const BusinessCentralItemSearchGroup(
              commonItemNo: '1012',
              totalInventory: 2523.9,
              variations: [
                BusinessCentralItemVariation(id: 'id-1', itemNo: '1012A01'),
                BusinessCentralItemVariation(id: 'id-2', itemNo: '1012A02'),
              ],
            ),
          );
        final stockLookupService = FakeStockLookupService();
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
          checkAvailabilityService: stockLookupService,
        );

        // 1-2. Enter "1012" and tap Search.
        await tester.enterText(find.byType(TextField), '1012');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        // 3-4. The fake catalogue service resolves to the exact 1012
        // group, and 1012A01 is visible as a variation row.
        expect(find.byKey(const ValueKey('variation-1012A01')), findsOneWidget);

        // 5. Tap the visible 1012A01 row's inline "Check" button.
        await _tapCheck(tester, '1012A01');

        // 6. Catalogue search was called exactly once, with "1012" only.
        expect(catalogueSearchService.calls, ['1012']);
        // 7. Stock lookup was called exactly once, with "1012A01".
        expect(stockLookupService.calls, ['1012A01']);
        // 8. Catalogue search was never called again — in particular
        // never with the selected exact itemNo "1012A01".
        expect(catalogueSearchService.calls, isNot(contains('1012A01')));
      });

      testWidgets('manually typing the exact itemNo and pressing Search calls '
          'catalogue search with it — a distinct user action from tapping '
          'an already-visible variation row', (tester) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = (query) =>
              ItemCatalogueSuggestions(query, const [
                BusinessCentralItemSearchGroup(
                  commonItemNo: '1012',
                  totalInventory: 2523.9,
                  variations: [
                    BusinessCentralItemVariation(id: 'id-1', itemNo: '1012A01'),
                  ],
                ),
              ]);
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), '1012A01');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(catalogueSearchService.calls, ['1012A01']);
        expect(find.text('Matching catalogues'), findsOneWidget);
      });

      testWidgets(
        'tapping the "Catalogue 1012 / N variations" header collapses and '
        're-expands the variation list without calling catalogue search or '
        'stock lookup',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = (query) => ItemCatalogueExactMatch(
              query,
              const BusinessCentralItemSearchGroup(
                commonItemNo: '1012',
                totalInventory: 2523.9,
                variations: [
                  BusinessCentralItemVariation(id: 'id-1', itemNo: '1012A01'),
                  BusinessCentralItemVariation(id: 'id-2', itemNo: '1012A02'),
                ],
              ),
            );
          final stockLookupService = FakeStockLookupService();
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
            checkAvailabilityService: stockLookupService,
          );

          await tester.enterText(find.byType(TextField), '1012');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();

          // Starts expanded: both variations visible, chevron pointing down.
          expect(
            find.byKey(const ValueKey('variation-1012A01')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('variation-1012A02')),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

          // Tap the header — collapses the list, chevron flips.
          await tester.ensureVisible(
            find.byKey(const ValueKey('catalogue-variations-header')),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('catalogue-variations-header')),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const ValueKey('variation-1012A01')), findsNothing);
          expect(find.byKey(const ValueKey('variation-1012A02')), findsNothing);
          expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
          expect(find.byIcon(Icons.expand_more_rounded), findsNothing);

          // Tap it again — re-expands.
          await tester.ensureVisible(
            find.byKey(const ValueKey('catalogue-variations-header')),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(const ValueKey('catalogue-variations-header')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('variation-1012A01')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('variation-1012A02')),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

          // Neither collapse nor re-expand ever touched catalogue search
          // (still exactly the one original "1012" call) or stock lookup
          // (never called at all — no variation was selected).
          expect(catalogueSearchService.calls, ['1012']);
          expect(stockLookupService.calls, isEmpty);
        },
      );

      testWidgets('locations are summed into one combined status, never a '
          'per-location breakdown, and the quantity is never shown', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = _singleVariationExactMatch;
        final stockLookupService = FakeStockLookupService()
          ..defaultResultBuilder = (rawCode) => StockLookupSuccess(
            rawCode,
            scannedAt: DateTime(2026, 1, 1),
            availabilityByLocation: const [
              // Two MT locations that individually sit at/below the 100 m
              // threshold but together (60 + 55 = 115) clear it.
              StockLocationAvailability(
                locationCode: 'LOC-01',
                remainingQuantity: 60,
                unitOfMeasureCode: 'MT',
              ),
              StockLocationAvailability(
                locationCode: 'LOC-02',
                remainingQuantity: 55,
                unitOfMeasureCode: 'MT',
              ),
            ],
          );
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'TEST-ITEM-01');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();
        await _tapCheck(tester, 'TEST-ITEM-01');

        // One combined pill, green (summed 115 m > 100), no location codes,
        // no numbers.
        expect(
          find.byKey(const ValueKey('variation-status-available')),
          findsOneWidget,
        );
        expect(_pillColor(tester, 'available'), AppColors.stockAvailableBg);
        expect(find.text('Available'), findsOneWidget);
        expect(find.text('LOC-01'), findsNothing);
        expect(find.text('LOC-02'), findsNothing);
        expect(find.textContaining('60'), findsNothing);
        expect(find.textContaining('55'), findsNothing);
      });

      group('combined status thresholds (quantity never shown)', () {
        Future<void> checkWith(
          WidgetTester tester,
          List<StockLocationAvailability> availability,
        ) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = _singleVariationExactMatch;
          final stockLookupService = FakeStockLookupService()
            ..defaultResultBuilder = (rawCode) => StockLookupSuccess(
              rawCode,
              scannedAt: DateTime(2026, 1, 1),
              availabilityByLocation: availability,
            );
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
            checkAvailabilityService: stockLookupService,
          );

          await tester.enterText(find.byType(TextField), 'ITEM-THRESHOLD');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();
          await _tapCheck(tester, 'ITEM-THRESHOLD');
        }

        Future<void> checkMeters(WidgetTester tester, num quantity) =>
            checkWith(tester, [
              StockLocationAvailability(
                locationCode: 'LOC-01',
                remainingQuantity: quantity,
                unitOfMeasureCode: 'MT',
              ),
            ]);

        testWidgets('0 m → red "Out of stock" pill, no location, no number', (
          tester,
        ) async {
          await checkMeters(tester, 0);

          expect(find.text('Out of stock'), findsOneWidget);
          expect(find.text('Available'), findsNothing);
          expect(find.text('LOC-01'), findsNothing);
          expect(_pillColor(tester, 'out'), AppColors.stockOutBg);
        });

        testWidgets('99 m → yellow "contact support" pill, not the quantity', (
          tester,
        ) async {
          await checkMeters(tester, 99);

          expect(find.text('Contact Support for inquiries'), findsOneWidget);
          expect(find.text('Available'), findsNothing);
          expect(find.textContaining('99'), findsNothing);
          expect(find.text('LOC-01'), findsNothing);
          expect(_pillColor(tester, 'low'), AppColors.stockLowBg);
        });

        testWidgets('100 m (the boundary) → yellow "contact support" pill', (
          tester,
        ) async {
          await checkMeters(tester, 100);

          expect(find.text('Contact Support for inquiries'), findsOneWidget);
          expect(find.text('Available'), findsNothing);
          expect(find.textContaining('100'), findsNothing);
          expect(_pillColor(tester, 'low'), AppColors.stockLowBg);
        });

        testWidgets('100.01 m → green "Available" pill, not the quantity', (
          tester,
        ) async {
          await checkMeters(tester, 100.01);

          expect(find.text('Available'), findsOneWidget);
          expect(find.textContaining('100.01'), findsNothing);
          expect(
            find.textContaining('Contact Support for inquiries'),
            findsNothing,
          );
          expect(_pillColor(tester, 'available'), AppColors.stockAvailableBg);
        });

        testWidgets('150 m → green "Available" pill, not the quantity', (
          tester,
        ) async {
          await checkMeters(tester, 150);

          expect(find.text('Available'), findsOneWidget);
          expect(find.textContaining('150'), findsNothing);
          expect(_pillColor(tester, 'available'), AppColors.stockAvailableBg);
        });

        testWidgets('a non-meters unit with stock → green "Available" pill, '
            'the meters threshold does not apply and no quantity is shown', (
          tester,
        ) async {
          await checkWith(tester, const [
            StockLocationAvailability(
              locationCode: 'LOC-01',
              remainingQuantity: 15,
              unitOfMeasureCode: 'YD',
            ),
          ]);

          expect(find.text('Available'), findsOneWidget);
          expect(find.text('15 YD'), findsNothing);
          expect(find.text('15'), findsNothing);
          expect(find.text('LOC-01'), findsNothing);
          expect(
            find.textContaining('Contact Support for inquiries'),
            findsNothing,
          );
          expect(_pillColor(tester, 'available'), AppColors.stockAvailableBg);
        });

        testWidgets('a non-meters unit summing to zero → red "Out of stock"', (
          tester,
        ) async {
          await checkWith(tester, const [
            StockLocationAvailability(
              locationCode: 'LOC-01',
              remainingQuantity: 0,
              unitOfMeasureCode: 'PCS',
            ),
          ]);

          expect(find.text('Out of stock'), findsOneWidget);
          expect(find.text('Available'), findsNothing);
          expect(_pillColor(tester, 'out'), AppColors.stockOutBg);
        });
      });

      testWidgets(
        'a second tap on the same row while its lookup is in flight does not '
        'start a duplicate',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = _singleVariationExactMatch;
          final gate = Completer<void>();
          final stockLookupService = FakeStockLookupService()..gate = gate;
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
            checkAvailabilityService: stockLookupService,
          );

          await tester.enterText(find.byType(TextField), 'ITEM-DUP');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();

          final checkButton = find.byKey(
            const ValueKey('variation-check-ITEM-DUP'),
          );
          await tester.ensureVisible(checkButton);
          await tester.pump();
          await tester.tap(checkButton);
          await tester.pump();

          expect(stockLookupService.callCount, 1);
          // While loading, the inline control is a spinner, not the button.
          expect(
            find.byKey(const ValueKey('variation-checking-ITEM-DUP')),
            findsOneWidget,
          );

          gate.complete();
          await tester.pumpAndSettle();

          expect(stockLookupService.callCount, 1);
        },
      );

      testWidgets('HTTP 401 (session expiry) shows no local error card', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = _singleVariationExactMatch;
        final stockLookupService = FakeStockLookupService()
          ..defaultResultBuilder = StockLookupSessionExpired.new;
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-401');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();
        await _tapCheck(tester, 'ITEM-401');

        expect(find.text('Available'), findsNothing);
        expect(
          find.text('Something went wrong. Please try again.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('HTTP 502 / a network failure shows a retryable error', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = _singleVariationExactMatch;
        final stockLookupService = FakeStockLookupService()
          ..defaultResultBuilder = StockLookupRetryableFailure.new;
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-502');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();
        await _tapCheck(tester, 'ITEM-502');

        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
      });

      testWidgets('HTTP 503 shows a distinct temporarily-unavailable error', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = _singleVariationExactMatch;
        final stockLookupService = FakeStockLookupService()
          ..defaultResultBuilder = StockLookupTemporarilyUnavailable.new;
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-503');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();
        await _tapCheck(tester, 'ITEM-503');

        expect(find.text('Temporarily unavailable.'), findsOneWidget);
      });

      testWidgets('a malformed successful response fails safely', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = _singleVariationExactMatch;
        final stockLookupService = FakeStockLookupService()
          ..defaultResultBuilder = StockLookupUnexpectedFailure.new;
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-MALFORMED');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();
        await _tapCheck(tester, 'ITEM-MALFORMED');

        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'retry (re-tapping the variation) after a failure sends a new API '
        'request and no mock result is ever shown',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = _singleVariationExactMatch;
          final stockLookupService = FakeStockLookupService()
            ..defaultResultBuilder = StockLookupRetryableFailure.new;
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
            checkAvailabilityService: stockLookupService,
          );

          await tester.enterText(find.byType(TextField), 'ITEM-RETRY');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();
          await _tapCheck(tester, 'ITEM-RETRY');

          expect(stockLookupService.callCount, 1);
          expect(
            find.text('Something went wrong. Please try again.'),
            findsOneWidget,
          );
          expect(find.text('320 yd available at Warehouse A.'), findsNothing);
          expect(find.textContaining('\$1,250.00'), findsNothing);

          stockLookupService.defaultResultBuilder = (rawCode) =>
              StockLookupSuccess(
                rawCode,
                scannedAt: DateTime(2026, 1, 1),
                availabilityByLocation: const [
                  StockLocationAvailability(
                    locationCode: 'LOC-01',
                    remainingQuantity: 150,
                    unitOfMeasureCode: 'MT',
                  ),
                ],
              );
          // The inline control is now a "Retry" button (same key); tapping it
          // sends a fresh request.
          await _tapCheck(tester, 'ITEM-RETRY');

          expect(stockLookupService.callCount, 2);
          expect(
            find.byKey(const ValueKey('variation-status-available')),
            findsOneWidget,
          );
          expect(find.text('Available'), findsOneWidget);
          expect(find.text('LOC-01'), findsNothing);
          expect(find.textContaining('150'), findsNothing);
          expect(
            find.text('Something went wrong. Please try again.'),
            findsNothing,
          );
        },
      );
    });

    group('catalogue suggestions', () {
      testWidgets(
        'selecting a suggestion shows its variations, then selecting a '
        'variation performs the exact stock lookup',
        (tester) async {
          final catalogueSearchService = FakeItemCatalogueSearchService()
            ..defaultResultBuilder = (query) => ItemCatalogueSuggestions(
              query,
              [
                const BusinessCentralItemSearchGroup(
                  commonItemNo: '1101',
                  totalInventory: 40,
                  variations: [
                    BusinessCentralItemVariation(id: 'id-1', itemNo: '110120'),
                    BusinessCentralItemVariation(id: 'id-2', itemNo: '110121'),
                  ],
                ),
                const BusinessCentralItemSearchGroup(
                  commonItemNo: '1610',
                  totalInventory: 12,
                  variations: [
                    BusinessCentralItemVariation(id: 'id-3', itemNo: '161012'),
                  ],
                ),
              ],
            );
          final stockLookupService = FakeStockLookupService();
          await _pumpHomeScreen(
            tester,
            390,
            catalogueSearchService: catalogueSearchService,
            checkAvailabilityService: stockLookupService,
          );

          await tester.enterText(find.byType(TextField), '1012');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pumpAndSettle();

          await tester.ensureVisible(
            find.byKey(const ValueKey('catalogue-group-1101')),
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('catalogue-group-1101')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('variation-110120')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('variation-110121')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('variation-161012')), findsNothing);

          await _tapCheck(tester, '110121');

          expect(stockLookupService.calls, ['110121']);
        },
      );

      testWidgets('"Matching catalogues" returns from a selected suggestion\'s '
          'variations to the suggestions list, clearing the selection', (
        tester,
      ) async {
        final catalogueSearchService = FakeItemCatalogueSearchService()
          ..defaultResultBuilder = (query) => ItemCatalogueSuggestions(query, [
            const BusinessCentralItemSearchGroup(
              commonItemNo: '1101',
              totalInventory: 40,
              variations: [
                BusinessCentralItemVariation(id: 'id-1', itemNo: '110120'),
              ],
            ),
            const BusinessCentralItemSearchGroup(
              commonItemNo: '1610',
              totalInventory: 12,
              variations: [
                BusinessCentralItemVariation(id: 'id-2', itemNo: '161012'),
              ],
            ),
          ]);
        await _pumpHomeScreen(
          tester,
          390,
          catalogueSearchService: catalogueSearchService,
        );

        await tester.enterText(find.byType(TextField), '1012');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('catalogue-group-1101')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('catalogue-group-1101')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('variation-110120')), findsOneWidget);

        await tester.ensureVisible(find.text('Matching catalogues'));
        await tester.pump();
        await tester.tap(find.text('Matching catalogues'));
        await tester.pumpAndSettle();

        expect(find.text('Catalogue 1101'), findsOneWidget);
        expect(find.text('Catalogue 1610'), findsOneWidget);
        expect(find.byKey(const ValueKey('variation-110120')), findsNothing);
      });
    });
  });

  testWidgets('Pull-to-refresh reloads the dashboard without errors', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BalanceCard), findsOneWidget);
  });

  group('Current Balance card', () {
    testWidgets('Loading state does not show mock or stale balance data', (
      tester,
    ) async {
      final pending = Completer<CurrentBalanceAmount>();
      await _pumpHomeScreenWithoutSettling(
        tester,
        FakeLastPaymentDataSource(entry: _sampleLastPaymentSummary()),
        currentBalanceSource: FakeCurrentBalanceDataSource(
          pendingFuture: pending.future,
        ),
      );

      expect(
        find.byKey(const ValueKey('current-balance-loading')),
        findsOneWidget,
      );
      expect(find.byType(BalanceCard), findsNothing);
      expect(find.text('\$42,850.00'), findsNothing);

      pending.complete(_sampleCurrentBalance);
      await tester.pump();
      await tester.pump();
    });

    testWidgets('Successful live data replaces the mock value', (tester) async {
      await _pumpHomeScreen(tester, 390);

      expect(
        find.descendant(
          of: find.byType(BalanceCard),
          matching: find.text('AED 15,320.75'),
        ),
        findsOneWidget,
      );
      expect(find.text('\$42,850.00'), findsNothing);
    });

    testWidgets(
      'A zero balance displays a real zero, never an empty card or mock '
      'data',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          390,
          currentBalanceSource: FakeCurrentBalanceDataSource(
            amount: const CurrentBalanceAmount(amount: 0, currencyCode: 'USD'),
          ),
        );

        expect(
          find.descendant(
            of: find.byType(BalanceCard),
            matching: find.text('USD 0.00'),
          ),
          findsOneWidget,
        );
        expect(find.text('\$42,850.00'), findsNothing);
      },
    );

    testWidgets(
      'A blank/unknown currency shows the plain amount, never a guessed '
      '"\$"',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          390,
          currentBalanceSource: FakeCurrentBalanceDataSource(
            amount: const CurrentBalanceAmount(
              amount: 500,
              currencyCode: null,
            ),
          ),
        );

        expect(
          find.descendant(
            of: find.byType(BalanceCard),
            matching: find.text('500.00'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(BalanceCard),
            matching: find.textContaining('\$'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('Failed live requests do not show mock financial data', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        currentBalanceSource: FakeCurrentBalanceDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('current-balance-error')),
        findsOneWidget,
      );
      expect(find.byType(BalanceCard), findsNothing);
      expect(find.text('\$42,850.00'), findsNothing);
    });

    testWidgets(
      'HTTP 401 (SessionExpiredException) shows no local error card',
      (tester) async {
        await _pumpHomeScreenWithoutSettling(
          tester,
          FakeLastPaymentDataSource(entry: _sampleLastPaymentSummary()),
          currentBalanceSource: FakeCurrentBalanceDataSource(
            error: const SessionExpiredException(),
          ),
        );

        expect(
          find.byKey(const ValueKey('current-balance-error')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('HTTP 502 shows a retryable upstream error', (tester) async {
      await _pumpHomeScreen(
        tester,
        390,
        currentBalanceSource: FakeCurrentBalanceDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        ),
      );

      final shell = find.byKey(const ValueKey('current-balance-error'));
      expect(shell, findsOneWidget);
      expect(
        find.descendant(
          of: shell,
          matching: find.text("Couldn't load data right now."),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: shell, matching: find.text('Retry')),
        findsOneWidget,
      );
    });

    testWidgets('HTTP 503 shows a distinct temporarily-unavailable error', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        currentBalanceSource: FakeCurrentBalanceDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralTemporarilyUnavailable(),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('current-balance-error')),
          matching: find.text('Temporarily unavailable.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('A network failure shows a retryable error', (tester) async {
      await _pumpHomeScreen(
        tester,
        390,
        currentBalanceSource: FakeCurrentBalanceDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralNetworkFailure(),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('current-balance-error')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsWidgets);
    });

    testWidgets(
      'An inconsistent-currency response shows a safe generic error',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          390,
          currentBalanceSource: FakeCurrentBalanceDataSource(
            error: const CurrentBalanceInconsistentCurrencyException({
              'AED',
              'USD',
            }),
          ),
        );

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('current-balance-error')),
            matching: find.text("Couldn't load data right now."),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Retry issues a new live request and a successful retry replaces the '
      'error state',
      (tester) async {
        final source = _FlakyCurrentBalanceDataSource();
        await _pumpHomeScreen(tester, 390, currentBalanceSource: source);
        expect(source.callCount, 1);
        expect(
          find.byKey(const ValueKey('current-balance-error')),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('current-balance-error')),
            matching: find.text('Retry'),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(source.callCount, 2);
        expect(
          find.byKey(const ValueKey('current-balance-error')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(BalanceCard),
            matching: find.text('AED 15,320.75'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Pull-to-refresh reloads Current Balance', (tester) async {
      final source = FakeCurrentBalanceDataSource(
        amount: _sampleCurrentBalance,
      );
      await _pumpHomeScreen(tester, 390, currentBalanceSource: source);
      expect(source.callCount, 1);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(source.callCount, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Stale-response protection: a slower initial load never overwrites a '
      'faster refresh result',
      (tester) async {
        final firstCall = Completer<CurrentBalanceAmount>();
        final secondCall = Completer<CurrentBalanceAmount>();
        final source = _SequencedCurrentBalanceDataSource([
          firstCall,
          secondCall,
        ]);

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
            home: HomeScreen(
              lastPaymentSource: FakeLastPaymentDataSource(
                entry: _sampleLastPaymentSummary(),
              ),
              currentBalanceSource: source,
              authService: _authServiceFor(),
              dashboardService: FakeHomeDashboardService(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        // Current Balance's first load (call #1) is still pending.
        expect(source.callCount, 1);

        await tester.fling(
          find.byType(RefreshIndicator),
          const Offset(0, 300),
          1000,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        // Pull-to-refresh started a second Current Balance load (call #2).
        expect(source.callCount, 2);

        // The newer call resolves first...
        secondCall.complete(
          const CurrentBalanceAmount(amount: 500.0, currencyCode: 'USD'),
        );
        await tester.pump();
        await tester.pump();

        // ...then the stale first call resolves after it — it must be
        // discarded, never overwriting the fresher result.
        firstCall.complete(
          const CurrentBalanceAmount(amount: 999.0, currencyCode: 'USD'),
        );
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(BalanceCard),
            matching: find.text('USD 500.00'),
          ),
          findsOneWidget,
        );
        expect(find.text('USD 999.00'), findsNothing);
      },
    );
  });

  group('Current Balance card navigation', () {
    testWidgets('Home screen renders the Current Balance card', (tester) async {
      await _pumpHomeScreen(tester, 390);

      expect(find.byType(BalanceCard), findsOneWidget);
    });

    testWidgets('Tapping the Current Balance card opens AccountBalanceScreen', (
      tester,
    ) async {
      await _pumpHomeScreen(tester, 390);

      await tester.tap(find.byType(BalanceCard));
      await _pumpRouteTransition(tester);

      expect(find.byType(AccountBalanceScreen), findsOneWidget);
    });

    testWidgets('Back navigation from AccountBalanceScreen returns to Home', (
      tester,
    ) async {
      await _pumpHomeScreen(tester, 390);

      await tester.tap(find.byType(BalanceCard));
      await _pumpRouteTransition(tester);
      expect(find.byType(AccountBalanceScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AccountBalanceScreen), findsNothing);
    });

    testWidgets(
      'Selecting Home from AccountBalanceScreen bottom nav returns to Home '
      'without creating a duplicate Home screen',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        await tester.tap(find.byType(BalanceCard));
        await _pumpRouteTransition(tester);
        expect(find.byType(AccountBalanceScreen), findsOneWidget);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(AccountBalanceScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Repeated opening and returning does not create navigation errors',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byType(BalanceCard));
          await _pumpRouteTransition(tester);
          expect(find.byType(AccountBalanceScreen), findsOneWidget);

          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(HomeScreen), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Passes Current Balance\'s already-loaded ledger-derived currency '
      'code into AccountBalanceScreen',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        await tester.tap(find.byType(BalanceCard));
        await _pumpRouteTransition(tester);

        final screen = tester.widget<AccountBalanceScreen>(
          find.byType(AccountBalanceScreen),
        );
        // _sampleCurrentBalance's fixture currency — see its doc comment.
        expect(screen.currencyCode, 'AED');
      },
    );

    testWidgets(
      'A blank/unresolved Current Balance currency passes null through, '
      'never a guessed code',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          390,
          currentBalanceSource: FakeCurrentBalanceDataSource(
            amount: const CurrentBalanceAmount(amount: 500, currencyCode: null),
          ),
        );

        await tester.tap(find.byType(BalanceCard));
        await _pumpRouteTransition(tester);

        final screen = tester.widget<AccountBalanceScreen>(
          find.byType(AccountBalanceScreen),
        );
        expect(screen.currencyCode, isNull);
      },
    );

    testWidgets(
      'Regression: Account Balance shows the ledger Currency_Code, never '
      'the login country region — a login country of AE with a ledger '
      'Currency_Code of USD must render USD, not AED',
      (tester) async {
        const sessionWithAeCountry = AuthSession(
          token: 'synthetic-id|synthetic-secret',
          userId: 7,
          username: 'sample.user',
          phone: '+9715xxxxxxxx',
          country: 'AE',
          clientId: 'ANCNAJJAR',
          mustChangePassword: false,
        );
        await _pumpHomeScreen(
          tester,
          390,
          authService: _authServiceFor(session: sessionWithAeCountry),
          currentBalanceSource: FakeCurrentBalanceDataSource(
            amount: const CurrentBalanceAmount(
              amount: 36711.73,
              currencyCode: 'USD',
            ),
          ),
        );

        await tester.tap(find.byType(BalanceCard));
        await _pumpRouteTransition(tester);

        final screen = tester.widget<AccountBalanceScreen>(
          find.byType(AccountBalanceScreen),
        );
        expect(screen.currencyCode, 'USD');
        expect(screen.currencyCode, isNot('AED'));
      },
    );
  });

  group('Current Balance demo mode', () {
    // TEMPORARY CLIENT DEMO MODE: covers resolveDefaultCurrentBalanceDataSource
    // (the pure resolver HomeScreen falls back to when no currentBalanceSource
    // is injected) for both DemoConfig.useDemoCurrentBalance branches,
    // regardless of the flag's current compiled-in value. With the flag now
    // false, HomeScreen's real default is LiveCurrentBalanceDataSource, so
    // the widget test below always injects a currentBalanceSource rather
    // than relying on the default (which would attempt real HTTP/secure
    // storage and hang in the widget-test sandbox).
    test('useDemo: true resolves to DemoCurrentBalanceDataSource, never the '
        'live ledger-entries integration', () {
      final source = resolveDefaultCurrentBalanceDataSource(useDemo: true);
      expect(source, isA<DemoCurrentBalanceDataSource>());
    });

    test('useDemo: false resolves to LiveCurrentBalanceDataSource, leaving the '
        'live Current Balance integration fully reachable', () {
      final source = resolveDefaultCurrentBalanceDataSource(useDemo: false);
      expect(source, isA<LiveCurrentBalanceDataSource>());
    });

    testWidgets(
      'With DemoConfig.useDemoCurrentBalance false, HomeScreen resolves its '
      'default CurrentBalanceDataSource to Live — so widget tests must '
      'always inject a currentBalanceSource to avoid real HTTP/secure '
      'storage, and whatever that injected source returns is what the card '
      'shows',
      (tester) async {
        // Distinct from DemoCurrentBalanceDataSource.mockBalance (AED
        // 18,450.75) on purpose: if HomeScreen ever silently fell back to
        // the demo source instead of the injected one, this assertion would
        // catch it.
        const liveStyleBalance = CurrentBalanceAmount(
          amount: 27610.40,
          currencyCode: 'AED',
        );

        await _pumpHomeScreen(
          tester,
          390,
          currentBalanceSource: FakeCurrentBalanceDataSource(
            amount: liveStyleBalance,
          ),
        );

        expect(
          find.descendant(
            of: find.byType(BalanceCard),
            matching: find.text('AED 27,610.40'),
          ),
          findsOneWidget,
        );
        expect(find.text('AED 18,450.75'), findsNothing);
      },
    );
  });

  group('Last Payment row', () {
    testWidgets(
      'Successful live result appears in the Last Payment row, with the '
      'absolute amount (never the negative sign) and the currencyCode as '
      'returned',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        expect(
          find.descendant(
            of: find.byType(LastPaymentCard),
            matching: find.text('AED 200.00'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(LastPaymentCard),
            matching: find.text('Jan 5'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(LastPaymentCard),
            matching: find.textContaining('-'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      '\$1,250.00 and Oct 24 are no longer used as production Last Payment '
      'data',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        expect(find.text('\$1,250.00'), findsNothing);
        expect(find.text('Oct 24'), findsNothing);
      },
    );

    testWidgets(
      'Shows the plain amount, no currency prefix — customer_details '
      'carries no currency field, so this never guesses \$ or any code',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          390,
          lastPaymentSource: FakeLastPaymentDataSource(
            entry: _sampleLastPaymentSummary(amount: -200.0),
          ),
        );

        expect(
          find.descendant(
            of: find.byType(LastPaymentCard),
            matching: find.text('200.00'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(LastPaymentCard),
            matching: find.textContaining('\$'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('Empty API data shows the no-payments state', (tester) async {
      await _pumpHomeScreen(
        tester,
        390,
        lastPaymentSource: FakeLastPaymentDataSource(entry: null),
      );

      expect(find.byKey(const ValueKey('last-payment-empty')), findsOneWidget);
      expect(find.text('No payments yet'), findsOneWidget);
      expect(find.byType(LastPaymentCard), findsNothing);
    });

    testWidgets('Loading state does not show mock or stale payment data', (
      tester,
    ) async {
      final pending = Completer<LastPaymentSummary?>();
      await _pumpHomeScreenWithoutSettling(
        tester,
        FakeLastPaymentDataSource(pendingFuture: pending.future),
      );

      expect(
        find.byKey(const ValueKey('last-payment-loading')),
        findsOneWidget,
      );
      expect(find.byType(LastPaymentCard), findsNothing);
      expect(find.text('\$1,250.00'), findsNothing);
      expect(find.text('Oct 24'), findsNothing);

      pending.complete(_sampleLastPaymentSummary());
      await tester.pump();
      await tester.pump();
    });

    testWidgets(
      'HTTP 401 (SessionExpiredException) shows no local error card',
      (tester) async {
        await _pumpHomeScreenWithoutSettling(
          tester,
          FakeLastPaymentDataSource(error: const SessionExpiredException()),
        );

        // The centralized session coordinator owns this case — Last
        // Payment must show no error card/toast of its own.
        expect(find.byKey(const ValueKey('last-payment-error')), findsNothing);
        expect(find.textContaining("Couldn't load"), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('HTTP 502 shows a retryable upstream error', (tester) async {
      await _pumpHomeScreen(
        tester,
        390,
        lastPaymentSource: FakeLastPaymentDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('last-payment-error')), findsOneWidget);
      expect(find.text("Couldn't load data right now."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('HTTP 503 shows a distinct temporarily-unavailable error', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        lastPaymentSource: FakeLastPaymentDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralTemporarilyUnavailable(),
          ),
        ),
      );

      expect(find.text('Temporarily unavailable.'), findsOneWidget);
    });

    testWidgets('A network failure shows a retryable error', (tester) async {
      await _pumpHomeScreen(
        tester,
        390,
        lastPaymentSource: FakeLastPaymentDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralNetworkFailure(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('last-payment-error')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('A malformed response shows a safe unexpected-data error', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        lastPaymentSource: FakeLastPaymentDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralProtocolFailure(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('last-payment-error')), findsOneWidget);
      expect(find.text("Couldn't load data right now."), findsOneWidget);
    });

    testWidgets(
      'Retry issues a new live request and a successful retry replaces the '
      'error state',
      (tester) async {
        final source = _FlakyLastPaymentDataSource();
        await _pumpHomeScreen(tester, 390, lastPaymentSource: source);
        expect(source.callCount, 1);
        expect(
          find.byKey(const ValueKey('last-payment-error')),
          findsOneWidget,
        );

        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(source.callCount, 2);
        expect(find.byKey(const ValueKey('last-payment-error')), findsNothing);
        expect(
          find.descendant(
            of: find.byType(LastPaymentCard),
            matching: find.text('AED 200.00'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Pull-to-refresh reloads the Last Payment row', (tester) async {
      final source = FakeLastPaymentDataSource(entry: _sampleLastPaymentSummary());
      await _pumpHomeScreen(tester, 390, lastPaymentSource: source);
      expect(source.callCount, 1);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(source.callCount, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('Home header username', () {
    AuthSession sessionWithUsername(String username) => AuthSession(
      token: _syntheticToken,
      userId: 7,
      username: username,
      phone: '+96890000000',
      country: 'OM',
      clientId: 'ANCNAJJAR',
      bcCustomerNo: 'SAMPLE-0001',
      mustChangePassword: false,
    );

    testWidgets(
      'Shows the authenticated username from the persisted session, never '
      'the mock name',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          390,
          authService: _authServiceFor(session: sessionWithUsername('rasha')),
        );

        expect(find.widgetWithText(HomeHeader, 'rasha'), findsOneWidget);
        expect(find.text('Alex Sterling'), findsNothing);
      },
    );

    testWidgets('A different authenticated username changes the header', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        authService: _authServiceFor(session: sessionWithUsername('nour')),
      );

      expect(find.widgetWithText(HomeHeader, 'nour'), findsOneWidget);
      expect(find.widgetWithText(HomeHeader, 'rasha'), findsNothing);
    });

    testWidgets(
      'Falls back to a safe generic label — never "Alex Sterling" — when no '
      'session is persisted',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          390,
          authService: _authServiceFor(session: null),
        );

        expect(find.widgetWithText(HomeHeader, 'User'), findsOneWidget);
        expect(find.text('Alex Sterling'), findsNothing);
      },
    );
  });
}
