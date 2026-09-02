// Widget checks for the Account Balance screen: hero card balance, Credit
// Utilization figures/progress bars, the graph-only Balance History section
// (From/To picker plus the real reconstructed-balance graph — no
// transaction list, no transaction-details navigation; live ledger data via
// LedgerBalanceHistoryDataSource), the Quick History list (live
// ledger-adapted rows — the one place individual ledger transactions are
// shown), the Export PDF flow, bottom navigation, narrow-width overflow
// safety, and that retired mock content (the old $42,850/+12.4%/Oct-12 note,
// and the 30/90/365-day preset selector) never returns.
//
// Display currency is not resolved by this screen at all (no AuthService/
// AuthSession.country region mapping): AccountBalanceScreen only accepts a
// `currencyCode` via constructor injection — the caller (HomeScreen) passes
// through Current Balance's already-loaded ledger-derived
// `CurrentBalanceAmount.currencyCode`. See home_screen_test.dart's "Current
// Balance card navigation" group for coverage of that hand-off, including
// the AE-login/USD-ledger regression case.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/models/balance_history_point.dart';
import 'package:anc_fabrics/models/business_central/customer_details.dart';
import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/account_balance_service.dart';
import 'package:anc_fabrics/services/balance_history_data_source.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/theme/app_colors.dart';
import 'package:anc_fabrics/widgets/avatar_initials_badge.dart';
import 'package:anc_fabrics/widgets/balance_history_date_range_picker.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';

import 'helpers/fake_account_balance_service.dart';
import 'helpers/fake_account_statement_exporter.dart';
import 'helpers/fake_balance_history_data_source.dart';
import 'helpers/fake_quick_history_data_source.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

// Ledger-adapted fixture rows, matching what
// adaptLedgerEntryToAccountTransaction would produce for real ledger
// entries — a neutral type/category, since the API contract does not
// define a credit/debit meaning for Amount's sign (see
// AccountTransactionType.neutral).
final _quickHistoryRows = [
  AccountTransaction(
    id: 'ledger-entry-1001',
    label: 'Invoice INV-TEST-001',
    amount: 100.50,
    type: AccountTransactionType.neutral,
    occurredAt: DateTime.utc(2026, 1, 5),
    category: AccountTransactionCategory.ledgerEntry,
    reference: 'INV-TEST-001',
  ),
  AccountTransaction(
    id: 'ledger-entry-1002',
    label: 'Payment PAY-TEST-002',
    amount: -50.00,
    type: AccountTransactionType.neutral,
    occurredAt: DateTime.utc(2026, 1, 3),
    category: AccountTransactionCategory.ledgerEntry,
    reference: 'PAY-TEST-002',
  ),
  AccountTransaction(
    id: 'ledger-entry-1003',
    label: 'Credit Memo CM-TEST-003',
    amount: 25.75,
    type: AccountTransactionType.neutral,
    occurredAt: DateTime.utc(2025, 12, 30),
    category: AccountTransactionCategory.ledgerEntry,
    reference: 'CM-TEST-003',
  ),
];

// Balance History's default fixture graph points.
final _balanceHistoryPoints = [
  BalanceHistoryPoint(
    date: DateTime.utc(2026, 1, 8),
    balance: 5000.00,
    currencyCode: 'AED',
  ),
  BalanceHistoryPoint(
    date: DateTime.utc(2026, 1, 10),
    balance: 5200.00,
    currencyCode: 'AED',
  ),
];

Future<void> _pumpAccountBalanceScreen(
  WidgetTester tester, {
  double width = 390,
  AccountBalanceService? service,
  FakeAccountStatementExporter? exporter,
  CurrentUserAvatarController? avatarController,
  String? currencyCode,
  FakeQuickHistoryDataSource? quickHistorySource,
  BalanceHistoryDataSource? balanceHistorySource,
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
      home: AccountBalanceScreen(
        service: service ?? FakeAccountBalanceService(),
        exporter: exporter ?? FakeAccountStatementExporter(),
        avatarController: avatarController,
        currencyCode: currencyCode,
        quickHistorySource:
            quickHistorySource ??
            FakeQuickHistoryDataSource(rows: _quickHistoryRows),
        balanceHistorySource:
            balanceHistorySource ??
            FakeBalanceHistoryDataSource(
              points: _balanceHistoryPoints,
              currencyCode: 'AED',
            ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Renders without exceptions', () {
    testWidgets('Builds successfully with fake service data', (tester) async {
      await _pumpAccountBalanceScreen(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Header', () {
    testWidgets('Shows the Indigo Loom brand and avatar initials badge', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.text('Indigo Loom'), findsOneWidget);
      // Derived from the mock signed-in user, "Alex Sterling".
      expect(find.text('AS'), findsOneWidget);
    });

    testWidgets('Reflects a shared avatar image and keeps showing the initials '
        'fallback when none is set', (tester) async {
      final avatarController = CurrentUserAvatarController();
      await _pumpAccountBalanceScreen(
        tester,
        avatarController: avatarController,
      );

      expect(find.text('AS'), findsOneWidget);
      var badge = tester.widget<AvatarInitialsBadge>(
        find.byKey(const ValueKey('account-balance-avatar')),
      );
      expect(badge.image, isNull);

      // A single pump (never pumpAndSettle) — the controller now holds a
      // network URL, and this only asserts the ImageProvider reference was
      // wired through the widget tree, not that a real fetch completed.
      avatarController.setAvatarUrl('http://127.0.0.1:9/avatars/7.jpg');
      await tester.pump();

      badge = tester.widget<AvatarInitialsBadge>(
        find.byKey(const ValueKey('account-balance-avatar')),
      );
      expect(badge.image, isNotNull);
    });
  });

  group('Global Account Balance hero card', () {
    testWidgets(
      'Shows the live balance with no hardcoded "\$", and Export PDF',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        expect(find.text('? 36,711.73'), findsWidgets);
        expect(find.text('Export PDF'), findsOneWidget);
      },
    );

    testWidgets('Never shows the retired mock balance or percent change', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      // Scoped to the hero card itself — this assertion is only about the
      // hero balance no longer showing the retired mock figure/percent-
      // change text (Credit Utilization's own figures are covered by the
      // "Credit Utilization card" group below).
      final heroCard = find.byKey(const ValueKey('account-balance-hero-card'));
      expect(
        find.descendant(of: heroCard, matching: find.text('\$42,850.00')),
        findsNothing,
      );
      expect(
        find.descendant(of: heroCard, matching: find.textContaining('%')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: heroCard,
          matching: find.textContaining('from last month'),
        ),
        findsNothing,
      );
    });

    testWidgets('Shows the initial-load spinner, then the balance', (
      tester,
    ) async {
      final pending = Completer<CustomerDetails>();
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AccountBalanceScreen(
            service: _PendingSummaryService(pending.future),
            exporter: FakeAccountStatementExporter(),
            quickHistorySource: FakeQuickHistoryDataSource(
              rows: _quickHistoryRows,
            ),
            balanceHistorySource: FakeBalanceHistoryDataSource(
              points: _balanceHistoryPoints,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('account-balance-loading')),
        findsOneWidget,
      );

      pending.complete(kFakeAccountSummary);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('account-balance-loading')),
        findsNothing,
      );
      expect(find.text('? 36,711.73'), findsWidgets);
    });

    testWidgets('Shows the error state with retry on a summary failure', (
      tester,
    ) async {
      final service = FakeAccountBalanceService(
        summaryError: const BusinessCentralFailureException(
          BusinessCentralUpstreamFailure(),
        ),
      );
      await _pumpAccountBalanceScreen(tester, service: service);

      expect(find.text('Unable to load account balance.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
      'Retrying after a summary failure re-invokes fetchAccountSummary',
      (tester) async {
        var callCount = 0;
        final failThenSucceed = _CountingFailOnceService(() => callCount++);
        await _pumpAccountBalanceScreen(tester, service: failThenSucceed);
        expect(callCount, 1);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(callCount, 2);
        expect(find.text('? 36,711.73'), findsWidgets);
      },
    );

    testWidgets('Opening the screen makes only the single unfiltered '
        'fetchAccountSummary request', (tester) async {
      final service = _CountingAccountBalanceService();
      await _pumpAccountBalanceScreen(tester, service: service);

      expect(service.fetchAccountSummaryCallCount, 1);
    });
  });

  group('Credit Utilization card', () {
    testWidgets(
      'Shows the "Credit Utilization" heading, not "Credit Information"',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        expect(find.text('Credit Utilization'), findsOneWidget);
        expect(find.text('Credit Information'), findsNothing);
      },
    );

    testWidgets(
      'Shows the Available Credit and Used Credit values with the "?" '
      'unknown-currency fallback when no currencyCode is passed in',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        expect(find.text('Available Credit'), findsOneWidget);
        expect(find.text('? 57,150.00'), findsOneWidget);
        expect(find.text('Used Credit'), findsOneWidget);
        expect(find.text('? 42,850.00'), findsOneWidget);
        expect(find.text('\$57,150.00'), findsNothing);
        expect(find.text('\$42,850.00'), findsNothing);
      },
    );

    testWidgets('Shows a progress bar for each row, derived from '
        'availableCredit/usedCredit, even when availableCredit is 0', (
      tester,
    ) async {
      final service = FakeAccountBalanceService(
        summary: const CustomerDetails(
          customerBalance: 36711.73,
          availableCredit: 0,
          usedCredit: 36711.73,
        ),
      );
      await _pumpAccountBalanceScreen(tester, service: service);

      final creditCard = find.byKey(const ValueKey('credit-utilization-card'));
      expect(
        find.descendant(
          of: creditCard,
          matching: find.byKey(
            const ValueKey('credit-utilization-progress-bar'),
          ),
        ),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Never shows the retired mock credit-limit-change note', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(
        find.text(
          'Your credit limit was recently increased by \$10,000 on Oct 12.',
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('credit-utilization-note')),
        findsNothing,
      );
    });
  });

  group('Passed-in display currency (ledger-derived, from Home)', () {
    // The confirmed live customer-details shape investigated for this
    // amendment: availableCredit == 0, usedCredit == customerBalance.
    const summary = CustomerDetails(
      customerBalance: 36711.73,
      availableCredit: 0,
      usedCredit: 36711.73,
    );

    for (final currency in ['AED', 'OMR', 'USD', 'IQD', 'SYP']) {
      testWidgets(
        'A $currency currencyCode renders on the hero balance and both '
        'Credit Utilization rows, with no numeric change',
        (tester) async {
          final service = FakeAccountBalanceService(summary: summary);
          await _pumpAccountBalanceScreen(
            tester,
            service: service,
            currencyCode: currency,
          );

          expect(find.text('$currency 36,711.73'), findsNWidgets(2));
          expect(find.text('$currency 0.00'), findsOneWidget);
          expect(find.text('? 36,711.73'), findsNothing);
        },
      );
    }

    testWidgets(
      'A null currencyCode (Current Balance not yet resolved) uses the '
      'existing "?" unknown-currency fallback, never a guessed code',
      (tester) async {
        final service = FakeAccountBalanceService(summary: summary);
        await _pumpAccountBalanceScreen(tester, service: service);

        expect(find.text('? 36,711.73'), findsNWidgets(2));
        expect(find.text('? 0.00'), findsOneWidget);
      },
    );

    testWidgets(
      'Does not perform currency conversion — the numeric figures are '
      'identical regardless of currencyCode, only the prefix changes',
      (tester) async {
        final service = FakeAccountBalanceService(summary: summary);
        await _pumpAccountBalanceScreen(
          tester,
          service: service,
          currencyCode: 'AED',
        );

        expect(find.text('AED 36,711.73'), findsNWidgets(2));
      },
    );

    testWidgets(
      'Does not depend on AuthSession.country/AuthService at all — the '
      'screen is constructible and renders correctly with only '
      'currencyCode supplied, no session-related parameter exists',
      (tester) async {
        final service = FakeAccountBalanceService(summary: summary);
        // No authService/session concept is passed — AccountBalanceScreen's
        // constructor no longer even has such a parameter (compile-time
        // proof), only currencyCode.
        await _pumpAccountBalanceScreen(
          tester,
          service: service,
          currencyCode: 'USD',
        );

        expect(find.text('USD 36,711.73'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Balance History card', () {
    testWidgets(
      'Renders below Credit Utilization, with From/To fields and the real '
      'balance-history graph only — never the retired 30/90/365-day preset '
      'selector, and never a transaction list',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        expect(
          find.byKey(const ValueKey('balance-history-from-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('balance-history-to-field')),
          findsOneWidget,
        );
        // The graph is restored and renders real, calculated points.
        expect(
          find.byKey(const ValueKey('balance-history-chart')),
          findsOneWidget,
        );
        // Balance History is graph-only — no transaction list beneath it.
        // Quick History (covered by its own group below) is the only place
        // individual ledger transactions render.
        expect(
          find.byKey(const ValueKey('balance-history-list')),
          findsNothing,
        );

        expect(find.text('30 Days'), findsNothing);
        expect(find.text('90 Days'), findsNothing);
        expect(find.text('1 Year'), findsNothing);
        expect(find.textContaining('Trend analysis'), findsNothing);
        // The retired mock series' fabricated balances must never appear.
        expect(find.text('\$38,100.00'), findsNothing);
        expect(find.text('\$42,850.00'), findsNothing);
        expect(find.text('\$24,500.00'), findsNothing);

        final creditCardTop = tester.getTopLeft(
          find.byKey(const ValueKey('credit-utilization-card')),
        );
        final historyCardTop = tester.getTopLeft(
          find.byKey(const ValueKey('balance-history-card')),
        );
        expect(historyCardTop.dy, greaterThan(creditCardTop.dy));
      },
    );

    testWidgets(
      'Defaults to the previous 30 days ending today (inclusive), sent as '
      'the From/To request to the data source',
      (tester) async {
        final source = FakeBalanceHistoryDataSource(
          points: _balanceHistoryPoints,
        );
        await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);

        final now = DateTime.now();
        final expectedTo = DateTime(now.year, now.month, now.day);
        final expectedFrom = expectedTo.subtract(const Duration(days: 29));

        expect(source.requestedRanges, hasLength(1));
        expect(source.requestedRanges.single.to, expectedTo);
        expect(source.requestedRanges.single.from, expectedFrom);
      },
    );

    testWidgets('Changing the From date reloads Balance History with the '
        'new range', (tester) async {
      final source = FakeBalanceHistoryDataSource(
        points: _balanceHistoryPoints,
      );
      await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);
      final callsBefore = source.callCount;

      final picker = tester.widget<BalanceHistoryDateRangePicker>(
        find.byType(BalanceHistoryDateRangePicker),
      );
      final newFrom = picker.to.subtract(const Duration(days: 5));
      picker.onFromChanged(newFrom);
      await tester.pumpAndSettle();

      expect(source.callCount, callsBefore + 1);
      expect(source.requestedRanges.last.from, newFrom);
      expect(source.requestedRanges.last.to, picker.to);
    });

    testWidgets('Changing From/To re-renders the chart with the newly fetched '
        'points — the graph itself recalculates, not only the request', (
      tester,
    ) async {
      final source = _RangeAwareBalanceHistorySource();
      await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);

      expect(source.callCount, 1);

      final picker = tester.widget<BalanceHistoryDateRangePicker>(
        find.byType(BalanceHistoryDateRangePicker),
      );
      picker.onFromChanged(picker.to.subtract(const Duration(days: 3)));
      await tester.pumpAndSettle();

      expect(source.callCount, 2);
      // The chart is still present and reflects the second call's points
      // (a different length series) — proves the graph itself was
      // recalculated and re-rendered, not just the underlying request.
      final chart = tester.widget<SizedBox>(
        find.byKey(const ValueKey('balance-history-chart')),
      );
      expect(chart, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Changing the To date reloads Balance History with the new '
        'range', (tester) async {
      final source = FakeBalanceHistoryDataSource(
        points: _balanceHistoryPoints,
      );
      await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);
      final callsBefore = source.callCount;

      final picker = tester.widget<BalanceHistoryDateRangePicker>(
        find.byType(BalanceHistoryDateRangePicker),
      );
      final newTo = picker.from.add(const Duration(days: 3));
      picker.onToChanged(newTo);
      await tester.pumpAndSettle();

      expect(source.callCount, callsBefore + 1);
      expect(source.requestedRanges.last.to, newTo);
      expect(source.requestedRanges.last.from, picker.from);
    });

    testWidgets(
      'Picking a From date after the current To date clamps To to match — '
      'never sends an invalid (From after To) range',
      (tester) async {
        final source = FakeBalanceHistoryDataSource(
          points: _balanceHistoryPoints,
        );
        await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);

        final picker = tester.widget<BalanceHistoryDateRangePicker>(
          find.byType(BalanceHistoryDateRangePicker),
        );
        final invalidFrom = picker.to.add(const Duration(days: 10));
        picker.onFromChanged(invalidFrom);
        await tester.pumpAndSettle();

        final lastRange = source.requestedRanges.last;
        expect(lastRange.from, invalidFrom);
        expect(lastRange.to, invalidFrom);
        expect(lastRange.to.isBefore(lastRange.from), isFalse);
      },
    );

    testWidgets('Picking a To date before the current From date clamps From to '
        'match — never sends an invalid (To before From) range', (
      tester,
    ) async {
      final source = FakeBalanceHistoryDataSource(
        points: _balanceHistoryPoints,
      );
      await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);

      final picker = tester.widget<BalanceHistoryDateRangePicker>(
        find.byType(BalanceHistoryDateRangePicker),
      );
      final invalidTo = picker.from.subtract(const Duration(days: 10));
      picker.onToChanged(invalidTo);
      await tester.pumpAndSettle();

      final lastRange = source.requestedRanges.last;
      expect(lastRange.to, invalidTo);
      expect(lastRange.from, invalidTo);
      expect(lastRange.to.isBefore(lastRange.from), isFalse);
    });

    testWidgets('Shows the loading spinner while fetching, then the real '
        'graph — never mock data first', (tester) async {
      final pending = Completer<BalanceHistoryData>();
      final source = FakeBalanceHistoryDataSource(
        pendingFuture: pending.future,
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
          home: AccountBalanceScreen(
            service: FakeAccountBalanceService(),
            exporter: FakeAccountStatementExporter(),
            quickHistorySource: FakeQuickHistoryDataSource(
              rows: _quickHistoryRows,
            ),
            balanceHistorySource: source,
          ),
        ),
      );
      // Two pumps: the first flushes the translation delegate's async asset
      // load (so the screen actually mounts and initState's fetches begin
      // — see `_pumpAccountBalanceScreen`'s original comment on this same
      // requirement); the second flushes fetchAccountSummary's/Quick
      // History's own immediately-resolving fakes, so the screen is fully
      // past the outer whole-screen loading state and Balance History's own
      // section-level loading state (the assertion below) is reachable.
      // Balance History's own future is a manually controlled Completer, so
      // it never resolves on its own no matter how many times this pumps.
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('balance-history-loading')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('balance-history-chart')), findsNothing);

      pending.complete(
        BalanceHistoryData(
          points: _balanceHistoryPoints,
          currencyCode: 'AED',
          hasMultipleCurrencies: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('balance-history-loading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('balance-history-chart')),
        findsOneWidget,
      );
    });

    testWidgets(
      'Points non-empty -> Balance History is loaded (renders the graph), '
      'even though there is no transaction list to key the state off of '
      'anymore',
      (tester) async {
        await _pumpAccountBalanceScreen(
          tester,
          balanceHistorySource: FakeBalanceHistoryDataSource(
            points: _balanceHistoryPoints,
          ),
        );

        expect(
          find.byKey(const ValueKey('balance-history-chart')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('balance-history-empty')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Points empty -> Balance History shows the empty state — regression '
      'coverage for the section state no longer being derived from the '
      'removed transaction list',
      (tester) async {
        await _pumpAccountBalanceScreen(
          tester,
          balanceHistorySource: FakeBalanceHistoryDataSource(points: const []),
        );

        expect(
          find.byKey(const ValueKey('balance-history-empty')),
          findsOneWidget,
        );
        expect(
          find.text('No transactions in this date range.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('balance-history-chart')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'A multi-currency response (points always empty) still shows the '
      'multi-currency explanatory state, never the generic empty state',
      (tester) async {
        await _pumpAccountBalanceScreen(
          tester,
          balanceHistorySource: FakeBalanceHistoryDataSource(
            hasMultipleCurrencies: true,
          ),
        );

        expect(
          find.byKey(const ValueKey('balance-history-multi-currency')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('balance-history-empty')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Shows an error state with retry on an API failure — never mock or '
      'stale data',
      (tester) async {
        final source = FakeBalanceHistoryDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        );
        await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);

        expect(
          find.byKey(const ValueKey('balance-history-error')),
          findsOneWidget,
        );
        expect(find.text("Couldn't load data right now."), findsOneWidget);
        expect(
          find.byKey(const ValueKey('balance-history-chart')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Retrying after a Balance History failure re-invokes the data source',
      (tester) async {
        final source = FakeBalanceHistoryDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralUpstreamFailure(),
          ),
        );
        await _pumpAccountBalanceScreen(tester, balanceHistorySource: source);
        final callsBefore = source.callCount;

        final retryButton = find.descendant(
          of: find.byKey(const ValueKey('balance-history-error')),
          matching: find.text('Retry'),
        );
        await tester.ensureVisible(retryButton);
        await tester.tap(retryButton);
        await tester.pumpAndSettle();

        expect(source.callCount, callsBefore + 1);
      },
    );
  });

  group('Quick History card', () {
    testWidgets(
      'Renders below the Balance History card with live ledger-adapted rows',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        expect(find.text('QUICK HISTORY'), findsOneWidget);

        final balanceHistoryTop = tester.getTopLeft(
          find.byKey(const ValueKey('balance-history-card')),
        );
        final quickHistoryTop = tester.getTopLeft(
          find.byKey(const ValueKey('quick-history-card')),
        );
        expect(quickHistoryTop.dy, greaterThan(balanceHistoryTop.dy));

        expect(find.text('Invoice INV-TEST-001'), findsOneWidget);
        expect(find.text('Payment PAY-TEST-002'), findsOneWidget);
        expect(find.text('Credit Memo CM-TEST-003'), findsOneWidget);
      },
    );

    testWidgets('No mock ledger rows flash before the data source resolves', (
      tester,
    ) async {
      final pending = Completer<List<AccountTransaction>>();
      final source = FakeQuickHistoryDataSource(pendingFuture: pending.future);
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AccountBalanceScreen(
            service: FakeAccountBalanceService(),
            exporter: FakeAccountStatementExporter(),
            quickHistorySource: source,
            balanceHistorySource: FakeBalanceHistoryDataSource(
              points: _balanceHistoryPoints,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('Invoice INV-TEST-001'), findsNothing);
      expect(find.byKey(const ValueKey('quick-history-card')), findsNothing);

      pending.complete(_quickHistoryRows);
      await tester.pumpAndSettle();
      expect(find.text('Invoice INV-TEST-001'), findsOneWidget);
    });

    testWidgets(
      'Ledger-adapted rows render with neutral styling, not invented credit/debit color',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        final invoiceAmount = tester.widget<Text>(find.text('\$100.50'));
        expect(invoiceAmount.style?.color, AppColors.textNavy);

        final paymentAmount = tester.widget<Text>(find.text('-\$50.00'));
        expect(paymentAmount.style?.color, AppColors.textNavy);
      },
    );

    testWidgets(
      'Tapping a row opens Transaction Details with the selected transaction',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        final row = find.byKey(
          const ValueKey('quick-history-row-ledger-entry-1001'),
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(find.text('Transaction Details'), findsOneWidget);

        final detailsCard = find.byKey(
          const ValueKey('account-transaction-details-card'),
        );
        expect(
          find.descendant(
            of: detailsCard,
            matching: find.text('Invoice INV-TEST-001'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: detailsCard, matching: find.text('\$100.50')),
          findsOneWidget,
        );
        // Neutral rows never show a "Credit"/"Debit" status line.
        expect(
          find.descendant(of: detailsCard, matching: find.text('Credit')),
          findsNothing,
        );
        expect(
          find.descendant(of: detailsCard, matching: find.text('Debit')),
          findsNothing,
        );
        expect(
          find.descendant(of: detailsCard, matching: find.text('INV-TEST-001')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Tapping See all shows the temporary placeholder SnackBar', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      final seeAllButton = find.byKey(
        const ValueKey('quick-history-see-all-button'),
      );
      await tester.ensureVisible(seeAllButton);
      await tester.tap(seeAllButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Full transaction history is not available yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shows a controlled empty state for a successful empty page', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(
        tester,
        quickHistorySource: FakeQuickHistoryDataSource(rows: const []),
      );

      expect(find.text('QUICK HISTORY'), findsOneWidget);
      expect(
        find.text('No account statement entries are available yet.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('quick-history-card')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Shows the account-not-linked message and preserves the rest of the '
      'screen',
      (tester) async {
        await _pumpAccountBalanceScreen(
          tester,
          quickHistorySource: FakeQuickHistoryDataSource(
            error: const BusinessCentralFailureException(
              BusinessCentralAccountNotLinked('unlinked customer'),
            ),
          ),
        );

        expect(
          find.text(
            "Your account isn't fully set up yet. Please contact support.",
          ),
          findsOneWidget,
        );
        // The rest of the screen is unaffected by a Quick-History-only
        // failure.
        expect(find.text('Export PDF'), findsOneWidget);
        expect(find.text('Available Credit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Shows "Temporarily unavailable." for a 503 outcome', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(
        tester,
        quickHistorySource: FakeQuickHistoryDataSource(
          error: const BusinessCentralFailureException(
            BusinessCentralTemporarilyUnavailable(),
          ),
        ),
      );

      expect(find.text('Temporarily unavailable.'), findsOneWidget);
    });

    testWidgets(
      'Shows the generic retry copy for an upstream/network/protocol failure',
      (tester) async {
        await _pumpAccountBalanceScreen(
          tester,
          quickHistorySource: FakeQuickHistoryDataSource(
            error: const BusinessCentralFailureException(
              BusinessCentralUpstreamFailure(),
            ),
          ),
        );

        expect(find.text("Couldn't load data right now."), findsOneWidget);
      },
    );

    testWidgets('Retrying after a failure re-invokes the data source', (
      tester,
    ) async {
      final source = FakeQuickHistoryDataSource(
        error: const BusinessCentralFailureException(
          BusinessCentralUpstreamFailure(),
        ),
      );
      await _pumpAccountBalanceScreen(tester, quickHistorySource: source);
      expect(source.callCount, 1);

      final retryButton = find.text('Retry').last;
      await tester.ensureVisible(retryButton);
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(source.callCount, 2);
    });

    testWidgets('A session-expired failure shows no error card and no toast', (
      tester,
    ) async {
      // The coordinator has already handled the 401 by the time
      // SessionExpiredException reaches this screen, so it deliberately
      // leaves Quick History's loading spinner in place forever (in a real
      // app the screen is off-stack by then) — pumpAndSettle would hang
      // waiting for that spinner to stop, so a bounded pump is used
      // instead.
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AccountBalanceScreen(
            service: FakeAccountBalanceService(),
            exporter: FakeAccountStatementExporter(),
            quickHistorySource: FakeQuickHistoryDataSource(
              error: const SessionExpiredException(),
            ),
            balanceHistorySource: FakeBalanceHistoryDataSource(
              points: _balanceHistoryPoints,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text("Couldn't load data right now."), findsNothing);
      expect(
        find.text(
          "Your account isn't fully set up yet. Please contact support.",
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Export PDF', () {
    testWidgets('Tapping Export PDF invokes the injected exporter', (
      tester,
    ) async {
      final exporter = FakeAccountStatementExporter();
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      expect(exporter.exportedData, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shows Generating... while export is pending', (tester) async {
      final pending = Completer<void>();
      final exporter = FakeAccountStatementExporter(pending: pending);
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pump();

      expect(find.text('Generating...'), findsOneWidget);
      expect(find.text('Export PDF'), findsNothing);

      pending.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Failed export shows the expected SnackBar', (tester) async {
      final exporter = FakeAccountStatementExporter(
        error: Exception('platform failure'),
      );
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not generate the account statement. Please try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Exporter receives the balance and credit utilization data', (
      tester,
    ) async {
      final exporter = FakeAccountStatementExporter();
      await _pumpAccountBalanceScreen(tester, exporter: exporter);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      final data = exporter.exportedData.single;
      expect(data.customerBalance, 36711.73);
      expect(data.creditUtilization.availableCredit, 57150.00);
      expect(data.creditUtilization.usedCredit, 42850.00);
      // No currencyCode passed into the screen in this test -> no guessed
      // currency reaches the export either.
      expect(data.currencyCode, isNull);
    });

    testWidgets('Exporter receives the passed-in ledger-derived currency '
        'code, agreeing with what the UI shows', (tester) async {
      final exporter = FakeAccountStatementExporter();
      await _pumpAccountBalanceScreen(
        tester,
        exporter: exporter,
        currencyCode: 'OMR',
      );

      expect(find.text('OMR 36,711.73'), findsWidgets);

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      final data = exporter.exportedData.single;
      expect(data.currencyCode, 'OMR');
    });

    testWidgets('Exporter receives the selected Balance History From/To '
        'range', (tester) async {
      final exporter = FakeAccountStatementExporter();
      final balanceHistorySource = FakeBalanceHistoryDataSource(
        points: _balanceHistoryPoints,
      );
      await _pumpAccountBalanceScreen(
        tester,
        exporter: exporter,
        balanceHistorySource: balanceHistorySource,
      );

      final picker = tester.widget<BalanceHistoryDateRangePicker>(
        find.byType(BalanceHistoryDateRangePicker),
      );
      final newFrom = picker.to.subtract(const Duration(days: 89));
      picker.onFromChanged(newFrom);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();

      final data = exporter.exportedData.single;
      expect(data.historyFrom, newFrom);
      expect(data.historyTo, picker.to);
    });

    testWidgets(
      'Exporter receives the live Quick History transactions shown on screen',
      (tester) async {
        final exporter = FakeAccountStatementExporter();
        await _pumpAccountBalanceScreen(tester, exporter: exporter);

        await tester.tap(find.text('Export PDF'));
        await tester.pumpAndSettle();

        final data = exporter.exportedData.single;
        expect(data.quickHistory.map((t) => t.id), [
          'ledger-entry-1001',
          'ledger-entry-1002',
          'ledger-entry-1003',
        ]);
      },
    );
  });

  group('Bottom navigation', () {
    testWidgets('Shows the Home, Orders, Support, and Profile tabs', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Reuses CustomBottomNav with exactly four destinations', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

      expect(find.byType(CustomBottomNav), findsOneWidget);
      expect(find.byType(CustomBottomNavItem), findsNWidgets(4));
      expect(find.text('Account Balance'), findsNothing);
    });

    testWidgets(
      'Selecting Home is safe when there is no screen to pop back to',
      (tester) async {
        await _pumpAccountBalanceScreen(tester);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountBalanceScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Selecting Orders, Support, and Profile pushes each screen', (
      tester,
    ) async {
      await _pumpAccountBalanceScreen(tester);

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
  });

  group('Responsive layout', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow at ${width}px width', (tester) async {
        await _pumpAccountBalanceScreen(tester, width: width);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Holds [fetchAccountSummary] on [pending] so a test can observe the
/// initial-load spinner before choosing exactly when/how it resolves.
class _PendingSummaryService implements AccountBalanceService {
  _PendingSummaryService(this.pending);

  final Future<CustomerDetails> pending;

  @override
  Future<CustomerDetails> fetchAccountSummary() => pending;
}

/// Fails the first [fetchAccountSummary] call, then succeeds with
/// [kFakeAccountSummary] on every subsequent call — lets a test exercise
/// the retry button's real re-fetch path.
class _CountingFailOnceService implements AccountBalanceService {
  _CountingFailOnceService(this._onSummaryCall);

  final void Function() _onSummaryCall;
  bool _hasFailedOnce = false;

  @override
  Future<CustomerDetails> fetchAccountSummary() async {
    _onSummaryCall();
    if (!_hasFailedOnce) {
      _hasFailedOnce = true;
      throw const BusinessCentralFailureException(
        BusinessCentralUpstreamFailure(),
      );
    }
    return kFakeAccountSummary;
  }
}

/// Counts [fetchAccountSummary] calls, so a test can assert the screen
/// makes exactly one customer-details request on open (no second,
/// date-filtered request for a Balance by Period section).
class _CountingAccountBalanceService implements AccountBalanceService {
  int fetchAccountSummaryCallCount = 0;

  @override
  Future<CustomerDetails> fetchAccountSummary() async {
    fetchAccountSummaryCallCount++;
    return kFakeAccountSummary;
  }
}

/// A [BalanceHistoryDataSource] whose returned points differ each call —
/// unlike [FakeBalanceHistoryDataSource]'s fixed canned data — so a test can
/// prove the chart actually re-renders with a *new* series after From/To
/// changes, not merely that a new request was sent.
class _RangeAwareBalanceHistorySource implements BalanceHistoryDataSource {
  int callCount = 0;

  @override
  Future<BalanceHistoryData> fetchBalanceHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    callCount++;
    // A different point count each call, so re-rendering with stale data
    // would be structurally detectable (not just value-detectable).
    final points = [
      for (var i = 0; i < callCount; i++)
        BalanceHistoryPoint(
          date: from.add(Duration(days: i)),
          balance: 1000.0 * callCount + i,
          currencyCode: 'AED',
        ),
    ];
    return BalanceHistoryData(
      points: points,
      currencyCode: 'AED',
      hasMultipleCurrencies: false,
    );
  }
}
