// Focused widget checks for BalanceHistoryCard, independent of the full
// Account Balance screen: heading/subtitle rendering, the From/To date-range
// picker, loading/empty/error states, the multi-currency explanatory state,
// and the real reconstructed-balance graph. Balance History is graph-only —
// no transaction list, no transaction-details navigation; see
// BalanceHistoryCard's doc comment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/balance_history_point.dart';
import 'package:anc_fabrics/widgets/balance_history_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

final _from = DateTime(2023, 10, 1);
final _to = DateTime(2023, 10, 30);

final _points = [
  BalanceHistoryPoint(
    date: DateTime(2023, 10, 1),
    balance: 5000.0,
    currencyCode: 'AED',
  ),
  BalanceHistoryPoint(
    date: DateTime(2023, 10, 10),
    balance: 4950.0,
    currencyCode: 'AED',
  ),
  BalanceHistoryPoint(
    date: DateTime(2023, 10, 20),
    balance: 5050.5,
    currencyCode: 'AED',
  ),
];

Future<void> _pumpCard(
  WidgetTester tester, {
  DateTime? from,
  DateTime? to,
  BalanceHistoryLoadState state = BalanceHistoryLoadState.loaded,
  List<BalanceHistoryPoint> points = const [],
  bool hasMultipleCurrencies = false,
  ValueChanged<DateTime>? onFromChanged,
  ValueChanged<DateTime>? onToChanged,
  String? errorMessage,
  VoidCallback? onRetry,
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
        body: BalanceHistoryCard(
          from: from ?? _from,
          to: to ?? _to,
          onFromChanged: onFromChanged ?? (_) {},
          onToChanged: onToChanged ?? (_) {},
          state: state,
          points: points,
          hasMultipleCurrencies: hasMultipleCurrencies,
          errorMessage: errorMessage,
          onRetry: onRetry,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Heading and subtitle', () {
    testWidgets('Shows the heading and a subtitle derived from From/To', (
      tester,
    ) async {
      await _pumpCard(tester, points: _points);

      expect(find.text('Balance History'), findsOneWidget);
      expect(
        find.text('Transactions from Oct 1, 2023 to Oct 30, 2023'),
        findsOneWidget,
      );
    });

    testWidgets(
      'The subtitle reflects From/To even while loading/empty/error — it '
      'does not depend on fetched data',
      (tester) async {
        await _pumpCard(tester, state: BalanceHistoryLoadState.loading);
        expect(
          find.text('Transactions from Oct 1, 2023 to Oct 30, 2023'),
          findsOneWidget,
        );
      },
    );
  });

  group('Date range picker', () {
    testWidgets('Shows both From and To fields with the selected dates', (
      tester,
    ) async {
      await _pumpCard(tester, points: _points);

      expect(
        find.byKey(const ValueKey('balance-history-from-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('balance-history-to-field')),
        findsOneWidget,
      );
      expect(find.text('Oct 1, 2023'), findsOneWidget);
      expect(find.text('Oct 30, 2023'), findsOneWidget);
    });
  });

  group('Loading state', () {
    testWidgets('Shows a spinner instead of the graph while loading', (
      tester,
    ) async {
      await _pumpCard(tester, state: BalanceHistoryLoadState.loading);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Empty state', () {
    testWidgets('Shows a clear "no transactions" message, never a blank '
        'chart or stale content', (tester) async {
      await _pumpCard(tester, state: BalanceHistoryLoadState.empty);

      expect(
        find.byKey(const ValueKey('balance-history-empty')),
        findsOneWidget,
      );
      expect(find.text('No transactions in this date range.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Error state', () {
    testWidgets('Shows the given error message and a retry button', (
      tester,
    ) async {
      var retried = false;
      await _pumpCard(
        tester,
        state: BalanceHistoryLoadState.error,
        errorMessage: "Couldn't load data right now.",
        onRetry: () => retried = true,
      );

      expect(find.text("Couldn't load data right now."), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });
  });

  group('Graph', () {
    testWidgets('Shows the real balance-history chart when points are '
        'supplied — the loaded state renders the graph only', (tester) async {
      await _pumpCard(tester, points: _points);

      expect(
        find.byKey(const ValueKey('balance-history-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('balance-history-multi-currency')),
        findsNothing,
      );
    });

    testWidgets(
      'Shows an explanatory message instead of a chart — never a summed '
      'multi-currency graph — when hasMultipleCurrencies is true',
      (tester) async {
        await _pumpCard(tester, hasMultipleCurrencies: true);

        expect(
          find.byKey(const ValueKey('balance-history-multi-currency')),
          findsOneWidget,
        );
        expect(
          find.text(
            "This period includes multiple currencies and can't be shown "
            'as a single balance graph.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('balance-history-chart')),
          findsNothing,
        );
      },
    );

    testWidgets('Renders below the From/To picker — heading, subtitle, '
        'picker, then graph, in that order', (tester) async {
      await _pumpCard(tester, points: _points);

      final pickerTop = tester.getTopLeft(
        find.byKey(const ValueKey('balance-history-from-field')),
      );
      final chartTop = tester.getTopLeft(
        find.byKey(const ValueKey('balance-history-chart')),
      );
      expect(chartTop.dy, greaterThan(pickerTop.dy));
    });

    testWidgets('Renders safely (an empty SizedBox) for an empty points '
        'list that is not a multi-currency block — a defensive fallback, '
        'not the production path (the screen maps empty points to the '
        'empty state instead)', (tester) async {
      await _pumpCard(tester, points: const []);

      expect(find.byKey(const ValueKey('balance-history-chart')), findsNothing);
      expect(
        find.byKey(const ValueKey('balance-history-multi-currency')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Never shows retired content', () {
    testWidgets('Never shows the retired "Trend analysis"/30-90-day preset '
        'chart copy', (tester) async {
      await _pumpCard(tester, points: _points);

      expect(find.textContaining('Trend analysis'), findsNothing);
      expect(find.text('30 Days'), findsNothing);
      expect(find.text('90 Days'), findsNothing);
      expect(find.text('1 Year'), findsNothing);
    });

    testWidgets('Never shows a transaction list or row beneath the graph', (
      tester,
    ) async {
      await _pumpCard(tester, points: _points);

      expect(find.byKey(const ValueKey('balance-history-list')), findsNothing);
    });
  });
}
