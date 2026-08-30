import 'dart:math' as math;

import '../models/balance_history_point.dart';
import '../models/balance_history_range.dart';

/// Deterministic, demo-only Balance History series, keyed by range.
///
/// NOT live: `customer-details?date_from/date_to` returns an identical
/// `customerBalance` for every 30-day/90-day/1-year range on this endpoint
/// — live black-box testing on 2026-08-30 confirmed only the echoed
/// `DateFilter` changes, so Business Central does not expose a genuine
/// historical series today. This generated series exists only so the
/// Balance History chart/section has something to render; it is never
/// presented as live data (see `BalanceHistoryDataSource`'s doc comment)
/// and is deliberately kept in its own file, isolated from the live
/// customer-details-backed summary/credit figures.
final Map<BalanceHistoryRange, List<BalanceHistoryPoint>>
kMockBalanceHistoryByRange = {
  // Dates are UTC so the day-count arithmetic in _generateMockSeries can't
  // be thrown off by a DST transition inside the range (e.g. Oct 29, 2023).
  BalanceHistoryRange.thirtyDays: _generateMockSeries(
    start: DateTime.utc(2023, 10, 1),
    end: DateTime.utc(2023, 10, 30),
    pointCount: 30,
    startBalance: 38100.00,
    endBalance: 42850.00,
  ),
  BalanceHistoryRange.ninetyDays: _generateMockSeries(
    start: DateTime.utc(2023, 8, 2),
    end: DateTime.utc(2023, 10, 30),
    pointCount: 30,
    startBalance: 31250.00,
    endBalance: 42850.00,
  ),
  BalanceHistoryRange.oneYear: _generateMockSeries(
    start: DateTime.utc(2022, 10, 30),
    end: DateTime.utc(2023, 10, 30),
    pointCount: 12,
    startBalance: 24500.00,
    endBalance: 42850.00,
  ),
};

/// Builds a deterministic, smoothly-trending mock series of [pointCount]
/// points evenly spaced between [start] and [end] inclusive, moving from
/// [startBalance] toward [endBalance].
///
/// Not random: a fixed sine "wiggle" layered on a linear trend, so repeated
/// runs/tests always see the same values.
List<BalanceHistoryPoint> _generateMockSeries({
  required DateTime start,
  required DateTime end,
  required int pointCount,
  required double startBalance,
  required double endBalance,
}) {
  final totalDays = end.difference(start).inDays;
  final swing = (endBalance - startBalance).abs() * 0.03;

  final points = <BalanceHistoryPoint>[
    for (var i = 0; i < pointCount; i++)
      _pointAt(
        start: start,
        totalDays: totalDays,
        pointCount: pointCount,
        index: i,
        startBalance: startBalance,
        endBalance: endBalance,
        swing: swing,
      ),
  ];

  points[points.length - 1] = BalanceHistoryPoint(
    date: points.last.date,
    balance: endBalance,
  );
  return points;
}

BalanceHistoryPoint _pointAt({
  required DateTime start,
  required int totalDays,
  required int pointCount,
  required int index,
  required double startBalance,
  required double endBalance,
  required double swing,
}) {
  final t = pointCount == 1 ? 1.0 : index / (pointCount - 1);
  final date = start.add(Duration(days: (totalDays * t).round()));
  final trend = startBalance + (endBalance - startBalance) * t;
  final wiggle = math.sin(index * 0.9) * swing;
  return BalanceHistoryPoint(
    date: date,
    balance: double.parse((trend + wiggle).toStringAsFixed(2)),
  );
}
