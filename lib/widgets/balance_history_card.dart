import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/balance_history_point.dart';
import '../models/balance_history_range.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';
import '../utils/date_time_format.dart';
import 'balance_history_range_selector.dart';

/// Bordered white card showing the Balance History line chart: a heading,
/// a date-range subtitle, the 30 Days/90 Days/1 Year selector, and the
/// chart itself with an interactive per-point tooltip.
///
/// Reusable: takes its points/selected range through the constructor rather
/// than reading a service directly, matching the Invoice Details cards'
/// convention. [points] must be non-empty and sorted oldest-first for the
/// subtitle and chart to render correctly.
class BalanceHistoryCard extends StatelessWidget {
  const BalanceHistoryCard({
    super.key,
    required this.points,
    required this.selectedRange,
    required this.onRangeChanged,
    required this.isLoading,
  });

  final List<BalanceHistoryPoint> points;
  final BalanceHistoryRange selectedRange;
  final ValueChanged<BalanceHistoryRange> onRangeChanged;

  /// Whether a new range's data is still being fetched (shows a spinner in
  /// place of the chart instead of a stale/empty one).
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('balance-history-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Balance History',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle,
            key: const ValueKey('balance-history-subtitle'),
            style: const TextStyle(fontSize: 12.5, color: AppColors.grayText),
          ),
          const SizedBox(height: 14),
          BalanceHistoryRangeSelector(
            selected: selectedRange,
            onChanged: onRangeChanged,
          ),
          const SizedBox(height: 18),
          SizedBox(
            key: const ValueKey('balance-history-chart'),
            height: 220,
            child: _buildChartArea(),
          ),
        ],
      ),
    );
  }

  String get _subtitle {
    if (points.isEmpty) return '';
    final startDate = points.first.date;
    final endDate = points.last.date;
    // Only drop the year from the start date when it matches the end
    // date's year (30/90-day ranges) — a range spanning two different
    // years (e.g. 1 Year) would otherwise read ambiguously without it.
    final start = startDate.year == endDate.year
        ? formatMonthDay(startDate)
        : formatDateOnly(startDate);
    final end = formatDateOnly(endDate);
    return 'Trend analysis for $start - $end';
  }

  Widget _buildChartArea() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }
    return _BalanceHistoryChart(points: points);
  }
}

/// The fl_chart line/area chart itself: a smooth teal line with a light
/// translucent area fill, minimal grid/axes, bottom-only date labels, and a
/// dark-navy tooltip on touch showing the date and formatted currency
/// value for the touched point.
class _BalanceHistoryChart extends StatelessWidget {
  const _BalanceHistoryChart({required this.points});

  final List<BalanceHistoryPoint> points;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].balance),
    ];
    final labelStep = (points.length / 4).ceil().clamp(1, points.length);
    final lastIndex = points.length - 1;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index > lastIndex) {
                  return const SizedBox.shrink();
                }
                final isLabeledStep = index % labelStep == 0;
                if (!isLabeledStep && index != lastIndex) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    formatMonthDay(points[index].date),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.grayText,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.primaryNavy,
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.round().clamp(0, lastIndex);
                final point = points[index];
                return LineTooltipItem(
                  '${formatDateOnly(point.date)}\n${formatCurrency(point.balance)}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.darkTeal,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.darkTeal.withValues(alpha: 0.22),
                  AppColors.darkTeal.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
