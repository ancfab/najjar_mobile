// Focused widget checks for BalanceHistoryCard, independent of the full
// Account Balance screen: heading/subtitle rendering, the range selector,
// the loading state, and empty-points safety.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/balance_history_point.dart';
import 'package:anc_fabrics/models/balance_history_range.dart';
import 'package:anc_fabrics/widgets/balance_history_card.dart';

final _points = [
  BalanceHistoryPoint(date: DateTime(2023, 10, 1), balance: 38100.00),
  BalanceHistoryPoint(date: DateTime(2023, 10, 15), balance: 40000.00),
  BalanceHistoryPoint(date: DateTime(2023, 10, 30), balance: 42850.00),
];

Future<void> _pumpCard(
  WidgetTester tester, {
  List<BalanceHistoryPoint> points = const [],
  BalanceHistoryRange selectedRange = BalanceHistoryRange.thirtyDays,
  bool isLoading = false,
  ValueChanged<BalanceHistoryRange>? onRangeChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BalanceHistoryCard(
          points: points,
          selectedRange: selectedRange,
          onRangeChanged: onRangeChanged ?? (_) {},
          isLoading: isLoading,
        ),
      ),
    ),
  );
}

void main() {
  group('Heading and subtitle', () {
    testWidgets('Shows the heading and a subtitle derived from the points', (
      tester,
    ) async {
      await _pumpCard(tester, points: _points);

      expect(find.text('Balance History'), findsOneWidget);
      expect(
        find.text('Trend analysis for Oct 1 - Oct 30, 2023'),
        findsOneWidget,
      );
    });
  });

  group('Range selector', () {
    testWidgets('Shows all three range options and calls onRangeChanged', (
      tester,
    ) async {
      BalanceHistoryRange? selected;
      await _pumpCard(
        tester,
        points: _points,
        onRangeChanged: (range) => selected = range,
      );

      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('90 Days'), findsOneWidget);
      expect(find.text('1 Year'), findsOneWidget);

      await tester.tap(find.text('1 Year'));
      await tester.pump();

      expect(selected, BalanceHistoryRange.oneYear);
    });
  });

  group('Loading state', () {
    testWidgets('Shows a spinner instead of the chart while loading', (
      tester,
    ) async {
      await _pumpCard(tester, points: const [], isLoading: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Empty points', () {
    testWidgets('Renders without crashing when there are no points yet', (
      tester,
    ) async {
      await _pumpCard(tester, points: const [], isLoading: false);

      expect(find.text('Balance History'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
