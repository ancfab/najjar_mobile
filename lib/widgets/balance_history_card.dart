import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/balance_history_point.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';
import '../utils/date_time_format.dart';
import 'balance_history_date_range_picker.dart';

/// Load state for the Balance History card, owned by `AccountBalanceScreen`
/// and mirroring the Quick History section's own loading/loaded/empty/error
/// states (`_QuickHistoryState`) so both ledger-backed sections behave
/// consistently.
enum BalanceHistoryLoadState { loading, loaded, empty, error }

/// Bordered white card showing the Balance History section, in this order:
/// heading, the From/To date-range picker, and the real reconstructed-balance
/// graph (see `LedgerBalanceHistoryDataSource`'s doc comment for the
/// calculation) — never fabricated data, and never a chart drawn from
/// unverified values. Graph-only: the individual ledger transaction list
/// lives on Quick History (`QuickHistoryCard`), not here.
///
/// Reusable: takes its points/state through the constructor rather than
/// reading a service directly, matching [QuickHistoryCard]'s convention.
class BalanceHistoryCard extends StatelessWidget {
  const BalanceHistoryCard({
    super.key,
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.state,
    required this.points,
    required this.hasMultipleCurrencies,
    this.errorMessage,
    this.onRetry,
  });

  final DateTime from;
  final DateTime to;
  final ValueChanged<DateTime> onFromChanged;
  final ValueChanged<DateTime> onToChanged;

  final BalanceHistoryLoadState state;

  /// Real, calculated graph points for the selected range — see
  /// `LedgerBalanceHistoryDataSource`'s doc comment. Ignored (never
  /// rendered) when [hasMultipleCurrencies] is true.
  final List<BalanceHistoryPoint> points;

  /// True when the range's balance-relevant entries span more than one
  /// distinct currency, so [points] cannot be combined into one graph —
  /// shows an explanatory message in the graph's place instead.
  final bool hasMultipleCurrencies;

  /// Controlled, safe user-facing copy for [BalanceHistoryLoadState.error] —
  /// resolved by the caller from the failure's `BusinessCentralOutcome`, the
  /// same way `AccountBalanceScreen` already resolves Quick History's error
  /// copy. Unused for every other [state].
  final String? errorMessage;

  /// Retries the current From/To fetch. Unused for every [state] other than
  /// [BalanceHistoryLoadState.error].
  final VoidCallback? onRetry;

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
          Text(
            context.t('balanceHistory.heading'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle(context),
            key: const ValueKey('balance-history-subtitle'),
            style: const TextStyle(fontSize: 12.5, color: AppColors.grayText),
          ),
          const SizedBox(height: 14),
          BalanceHistoryDateRangePicker(
            from: from,
            to: to,
            onFromChanged: onFromChanged,
            onToChanged: onToChanged,
          ),
          const SizedBox(height: 18),
          _buildContent(context),
        ],
      ),
    );
  }

  String _subtitle(BuildContext context) {
    // Derived directly from the selected From/To — always renderable, even
    // while [state] is loading/empty/error.
    return context.t(
      'balanceHistory.subtitle',
      params: {'start': formatDateOnly(from), 'end': formatDateOnly(to)},
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (state) {
      case BalanceHistoryLoadState.loading:
        return const Padding(
          key: ValueKey('balance-history-loading'),
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      case BalanceHistoryLoadState.empty:
        return Padding(
          key: const ValueKey('balance-history-empty'),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            context.t('balanceHistory.emptyRange'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grayText, fontSize: 13),
          ),
        );
      case BalanceHistoryLoadState.error:
        return Padding(
          key: const ValueKey('balance-history-error'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(
                errorMessage ?? context.t('accountBalance.errorGeneric'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grayText, fontSize: 13),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onRetry,
                  child: Text(context.t('common.retry')),
                ),
              ],
            ],
          ),
        );
      case BalanceHistoryLoadState.loaded:
        return _buildGraphArea(context);
    }
  }

  Widget _buildGraphArea(BuildContext context) {
    if (hasMultipleCurrencies) {
      return Padding(
        key: const ValueKey('balance-history-multi-currency'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          context.t('balanceHistory.multipleCurrencies'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.grayText, fontSize: 13),
        ),
      );
    }
    if (points.isEmpty) {
      // Defensive: production never reaches [BalanceHistoryLoadState.loaded]
      // with empty points when `hasMultipleCurrencies` is false (see
      // `LedgerBalanceHistoryDataSource`, which always emits at least the
      // opening-balance point), but this widget must still render safely
      // for any caller/test that supplies an empty list.
      return const SizedBox.shrink();
    }
    return SizedBox(
      key: const ValueKey('balance-history-chart'),
      height: 220,
      child: _BalanceHistoryChart(points: points),
    );
  }
}

/// The fl_chart line/area chart itself: a smooth teal line with a light
/// translucent area fill, minimal grid/axes, bottom-only date labels, and a
/// dark-navy tooltip on touch showing the date and formatted currency value
/// for the touched point. Restored from the app's original Balance History
/// design (see git history), now fed by real reconstructed-balance
/// [BalanceHistoryPoint]s instead of fabricated ones.
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
                  '${formatDateOnly(point.date)}\n'
                  '${formatCurrencyOrUnknown(point.balance, currencyCode: point.currencyCode)}',
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
