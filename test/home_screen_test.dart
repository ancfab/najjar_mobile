//The test folder contains automated Flutter widget tests. We added Home screen tests to validate navigation, responsive layout, catalogue lookup states, and pull-to-refresh behavior. These tests do not affect the production app; they are only used during development to make sure future changes do not break the UI.
// Widget checks for the Home screen: narrow-width overflow safety and the
// navigation wiring for the Scan CTA and bottom tab bar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/payment_entry.dart';
import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/scan_stock_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/current_balance_data_source.dart';
import 'package:anc_fabrics/services/current_balance_service.dart';
import 'package:anc_fabrics/services/demo_current_balance_data_source.dart';
import 'package:anc_fabrics/services/last_payment_data_source.dart';
import 'package:anc_fabrics/services/stock_lookup_service.dart';
import 'package:anc_fabrics/widgets/availability_search_card.dart';
import 'package:anc_fabrics/widgets/balance_card.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';
import 'package:anc_fabrics/widgets/last_payment_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

import 'helpers/fake_current_balance_data_source.dart';
import 'helpers/fake_last_payment_data_source.dart';
import 'helpers/fake_stock_lookup_service.dart';

/// A canned live [PaymentEntry] matching the confirmed API contract's
/// example payload (negative `amount`, non-USD `currencyCode`), used as the
/// default Last Payment fixture so pre-existing Home screen tests (that
/// don't care about Last Payment specifically) get a fast, deterministic,
/// non-mock result instead of hitting real HTTP/secure storage — which
/// never resolves in this widget-test sandbox (see AccountBalanceScreen's
/// Quick History tests for the same issue with a live data source default).
PaymentEntry _samplePaymentEntry({
  int entryNo = 2001,
  String postingDate = '2026-01-05',
  String currencyCode = 'AED',
  double amount = -200.0,
  double remainingAmount = 0,
}) {
  return PaymentEntry.fromJson({
    'entryNo': entryNo,
    'postingDate': postingDate,
    'documentNo': 'REC-TEST-101',
    'customerNo': 'CLNT-0001',
    'customerName': 'Test Customer One',
    'currencyCode': currencyCode,
    'amount': amount,
    'remainingAmount': remainingAmount,
    'open': false,
    'dueDate': postingDate,
  });
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
            FakeLastPaymentDataSource(entry: _samplePaymentEntry()),
        currentBalanceSource:
            currentBalanceSource ??
            FakeCurrentBalanceDataSource(amount: _sampleCurrentBalance),
        // Check Availability only performs a lookup on user action (unlike
        // Last Payment, it never auto-fetches on initState), so this fake
        // is never actually invoked by tests that don't search — it exists
        // so a test that DOES search never accidentally reaches the live
        // ApiStockLookupService default (real HTTP/secure storage).
        checkAvailabilityService:
            checkAvailabilityService ?? FakeStockLookupService(),
      ),
    ),
  );
  await tester.pump();
  // Home screen loads dashboard data via a mock delay on initState; advance
  // past it explicitly since pumpAndSettle won't wait for a bare Timer that
  // isn't tied to a scheduled frame.
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
  Future<PaymentEntry?> fetchLatestPayment() async {
    callCount++;
    if (callCount == 1) {
      throw const BusinessCentralFailureException(
        BusinessCentralUpstreamFailure(),
      );
    }
    return _samplePaymentEntry();
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
    'Catalogue lookup shows a validation error on empty input without '
    'calling the API',
    (tester) async {
      final stockLookupService = FakeStockLookupService();
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();

      expect(find.text('Please enter a catalogue code.'), findsOneWidget);
      expect(stockLookupService.callCount, 0);
    },
  );

  testWidgets('Catalogue lookup shows loading then a success result', (
    tester,
  ) async {
    final gate = Completer<void>();
    final stockLookupService = FakeStockLookupService()
      ..gate = gate
      ..defaultResultBuilder = (rawCode) => StockLookupSuccess(
        rawCode,
        scannedAt: DateTime(2026, 1, 1),
        description: 'Test Fabric',
        availabilityByLocation: const [
          StockLocationAvailability(
            locationCode: 'LOC-01',
            remainingQuantity: 80,
            unitOfMeasureCode: 'MT',
          ),
        ],
      );
    await _pumpHomeScreen(
      tester,
      390,
      checkAvailabilityService: stockLookupService,
    );

    await tester.enterText(find.byType(TextField), 'TEST-ITEM-01');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(stockLookupService.calls, ['TEST-ITEM-01']);

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.text('Test Fabric\n80 MT available at LOC-01.'),
      findsOneWidget,
    );
  });

  testWidgets('Catalogue lookup shows a no-results state for unknown codes', (
    tester,
  ) async {
    final stockLookupService = FakeStockLookupService()
      ..defaultResultBuilder = StockLookupNotFound.new;
    await _pumpHomeScreen(
      tester,
      390,
      checkAvailabilityService: stockLookupService,
    );

    await tester.enterText(find.byType(TextField), 'UNKNOWN-CODE');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('No availability found for "UNKNOWN-CODE".'),
      findsOneWidget,
    );
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

    testWidgets('surrounding whitespace is trimmed before the lookup', (
      tester,
    ) async {
      final stockLookupService = FakeStockLookupService();
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), '  TEST-ITEM-01  ');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(stockLookupService.calls, ['TEST-ITEM-01']);
    });

    testWidgets('a meaningful internal space is preserved exactly', (
      tester,
    ) async {
      final stockLookupService = FakeStockLookupService();
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), '  1038 01  ');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(stockLookupService.calls, ['1038 01']);
    });

    testWidgets('multiple locations and different units remain separate, never '
        'combined into one total', (tester) async {
      final stockLookupService = FakeStockLookupService()
        ..defaultResultBuilder = (rawCode) => StockLookupSuccess(
          rawCode,
          scannedAt: DateTime(2026, 1, 1),
          availabilityByLocation: const [
            StockLocationAvailability(
              locationCode: 'LOC-01',
              remainingQuantity: 80,
              unitOfMeasureCode: 'MT',
            ),
            StockLocationAvailability(
              locationCode: 'LOC-02',
              remainingQuantity: 15,
              unitOfMeasureCode: 'YD',
            ),
          ],
        );
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), 'TEST-ITEM-01');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('80 MT available at LOC-01.\n15 YD available at LOC-02.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'duplicate submissions are prevented while a lookup is active',
      (tester) async {
        final gate = Completer<void>();
        final stockLookupService = FakeStockLookupService()..gate = gate;
        await _pumpHomeScreen(
          tester,
          390,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-DUP');
        await tester.tap(searchButtonFinder);
        await tester.pump();

        expect(stockLookupService.callCount, 1);

        // A further tap while loading (the button now shows a spinner,
        // onTap: null) must not start a second lookup.
        await tester.tap(searchButtonFinder, warnIfMissed: false);
        await tester.pump();

        expect(stockLookupService.callCount, 1);

        gate.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'keyboard submission and the search button use the same lookup logic',
      (tester) async {
        final stockLookupService = FakeStockLookupService()
          ..defaultResultBuilder = (rawCode) => StockLookupSuccess(
            rawCode,
            scannedAt: DateTime(2026, 1, 1),
            availabilityByLocation: const [
              StockLocationAvailability(
                locationCode: 'LOC-01',
                remainingQuantity: 80,
                unitOfMeasureCode: 'MT',
              ),
            ],
          );
        await _pumpHomeScreen(
          tester,
          390,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-KB');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(stockLookupService.calls, ['ITEM-KB']);
        expect(
          find.descendant(
            of: find.byType(AvailabilitySearchCard),
            matching: find.textContaining('available'),
          ),
          findsOneWidget,
          reason:
              'the default StockLookupSuccess fixture always yields a '
              'success result, whichever code path triggered it',
        );
      },
    );

    testWidgets('HTTP 401 (session expiry) shows no local error card', (
      tester,
    ) async {
      final stockLookupService = FakeStockLookupService()
        ..defaultResultBuilder = StockLookupSessionExpired.new;
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), 'ITEM-401');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('available'), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('HTTP 502 / a network failure shows a retryable error', (
      tester,
    ) async {
      final stockLookupService = FakeStockLookupService()
        ..defaultResultBuilder = StockLookupRetryableFailure.new;
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), 'ITEM-502');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('HTTP 503 shows a distinct temporarily-unavailable error', (
      tester,
    ) async {
      final stockLookupService = FakeStockLookupService()
        ..defaultResultBuilder = StockLookupTemporarilyUnavailable.new;
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), 'ITEM-503');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Temporarily unavailable.'), findsOneWidget);
    });

    testWidgets('a malformed successful response fails safely', (tester) async {
      final stockLookupService = FakeStockLookupService()
        ..defaultResultBuilder = StockLookupUnexpectedFailure.new;
      await _pumpHomeScreen(
        tester,
        390,
        checkAvailabilityService: stockLookupService,
      );

      await tester.enterText(find.byType(TextField), 'ITEM-MALFORMED');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'retry after a failure sends a new API request and no mock result is '
      'ever shown',
      (tester) async {
        final stockLookupService = FakeStockLookupService()
          ..defaultResultBuilder = StockLookupRetryableFailure.new;
        await _pumpHomeScreen(
          tester,
          390,
          checkAvailabilityService: stockLookupService,
        );

        await tester.enterText(find.byType(TextField), 'ITEM-RETRY');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

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
                  remainingQuantity: 80,
                  unitOfMeasureCode: 'MT',
                ),
              ],
            );
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();

        expect(stockLookupService.callCount, 2);
        expect(find.text('80 MT available at LOC-01.'), findsOneWidget);
        expect(
          find.text('Something went wrong. Please try again.'),
          findsNothing,
        );
      },
    );
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
        FakeLastPaymentDataSource(entry: _samplePaymentEntry()),
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

    testWidgets('A blank/unknown currency shows "?", never a guessed "\$"', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        currentBalanceSource: FakeCurrentBalanceDataSource(
          amount: const CurrentBalanceAmount(amount: 500, currencyCode: null),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(BalanceCard),
          matching: find.text('? 500.00'),
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
    });

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
          FakeLastPaymentDataSource(entry: _samplePaymentEntry()),
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
                entry: _samplePaymentEntry(),
              ),
              currentBalanceSource: source,
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
  });

  group('Current Balance demo mode', () {
    // TEMPORARY CLIENT DEMO MODE: covers resolveDefaultCurrentBalanceDataSource
    // (the pure resolver HomeScreen falls back to when no currentBalanceSource
    // is injected) for both DemoConfig.useDemoCurrentBalance branches,
    // regardless of the flag's current compiled-in value, plus the actual
    // default-injection behavior at the flag's current value.
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
      'With no currentBalanceSource injected, the demo flag shows the mock '
      'balance without reaching the live ledger-entries endpoint',
      (tester) async {
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
                entry: _samplePaymentEntry(),
              ),
              checkAvailabilityService: FakeStockLookupService(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        // With DemoConfig.useDemoCurrentBalance false, this would instead
        // fall back to LiveCurrentBalanceDataSource (real HTTP/secure
        // storage), which never resolves in this widget-test sandbox and
        // would leave the loading spinner animating forever — pumpAndSettle
        // completing at all is itself evidence the demo path, not the live
        // one, was taken.
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(BalanceCard),
            matching: find.text('AED 18,450.75'),
          ),
          findsOneWidget,
        );
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

    testWidgets('remainingAmount is never used as the displayed amount', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        lastPaymentSource: FakeLastPaymentDataSource(
          entry: _samplePaymentEntry(amount: -200.0, remainingAmount: 999.99),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(LastPaymentCard),
          matching: find.text('AED 200.00'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('999.99'), findsNothing);
    });

    testWidgets('A blank currencyCode never defaults to USD/\$', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        390,
        lastPaymentSource: FakeLastPaymentDataSource(
          entry: _samplePaymentEntry(currencyCode: ''),
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
    });

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
      final pending = Completer<PaymentEntry?>();
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

      pending.complete(_samplePaymentEntry());
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
      final source = FakeLastPaymentDataSource(entry: _samplePaymentEntry());
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
}
