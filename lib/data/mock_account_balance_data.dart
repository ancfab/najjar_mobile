import 'dart:math' as math;

import '../models/account_balance_summary.dart';
import '../models/balance_history_point.dart';
import '../models/balance_history_range.dart';
import '../models/credit_utilization_data.dart';

// TODO(api): Replace mock account-balance summary and credit-utilization
// data after the backend endpoint and response contract are confirmed.
const AccountBalanceSummary kMockAccountBalanceSummary = AccountBalanceSummary(
  currentBalance: 42850.00,
  percentChangeFromLastMonth: 12.4,
  changePeriodLabel: 'from last month',
);

// TODO(api): Replace mock account-balance summary and credit-utilization
// data after the backend endpoint and response contract are confirmed.
const CreditUtilizationData kMockCreditUtilizationData = CreditUtilizationData(
  totalCredit: 100000.00,
  availableCredit: 57150.00,
  usedCredit: 42850.00,
  creditLimitChangeNote:
      'Your credit limit was recently increased by \$10,000 on Oct 12.',
);

/// Builds a deterministic, smoothly-trending mock series of [pointCount]
/// points evenly spaced between [start] and [end] inclusive, moving from
/// [startBalance] toward [endBalance].
///
/// Not random: a fixed sine "wiggle" layered on a linear trend, so repeated
/// runs/tests always see the same values. The final point is forced to
/// exactly [endBalance] so every range's chart ends at the same current
/// balance shown in the hero card.
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
  // start/end are UTC (see kMockBalanceHistoryByRange) so this addition
  // isn't thrown off by a DST transition falling inside the range.
  final date = start.add(Duration(days: (totalDays * t).round()));
  final trend = startBalance + (endBalance - startBalance) * t;
  final wiggle = math.sin(index * 0.9) * swing;
  return BalanceHistoryPoint(
    date: date,
    balance: double.parse((trend + wiggle).toStringAsFixed(2)),
  );
}

// TODO(api): Replace mock balance-history points with API data for the
// selected 30-day, 90-day, or 1-year range.
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
