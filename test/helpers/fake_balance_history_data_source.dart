// Fake BalanceHistoryDataSource for AccountBalanceScreen tests: returns a
// canned BalanceHistoryData or throws a canned exception, without exercising
// real HTTP or secure storage, and records the exact From/To range requested
// so a test can assert what the screen sent.

import 'package:anc_fabrics/models/balance_history_point.dart';
import 'package:anc_fabrics/services/balance_history_data_source.dart';

class FakeBalanceHistoryDataSource implements BalanceHistoryDataSource {
  FakeBalanceHistoryDataSource({
    List<BalanceHistoryPoint>? points,
    this.currencyCode,
    this.hasMultipleCurrencies = false,
    this.error,
    this.pendingFuture,
  }) : points = points ?? const [];

  /// The graph points `fetchBalanceHistory` resolves with.
  final List<BalanceHistoryPoint> points;

  final String? currencyCode;

  /// When true, resolves with empty [points], matching
  /// [BalanceHistoryData.hasMultipleCurrencies]'s real contract.
  final bool hasMultipleCurrencies;

  /// When set, thrown from [fetchBalanceHistory] instead of resolving.
  final Object? error;

  /// When set, awaited instead of resolving immediately — lets a test
  /// observe the loading state before controlling exactly when/how the
  /// call completes.
  final Future<BalanceHistoryData>? pendingFuture;

  int callCount = 0;

  /// Every `(from, to)` pair this fake was called with, in call order — so
  /// a test can assert the default range and each subsequent selection
  /// without depending on the screen's private state.
  final List<({DateTime from, DateTime to})> requestedRanges = [];

  @override
  Future<BalanceHistoryData> fetchBalanceHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    callCount++;
    requestedRanges.add((from: from, to: to));
    if (pendingFuture != null) return pendingFuture!;
    if (error != null) throw error!;
    return BalanceHistoryData(
      points: points,
      currencyCode: currencyCode,
      hasMultipleCurrencies: hasMultipleCurrencies,
    );
  }
}
