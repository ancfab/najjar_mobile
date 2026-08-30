import '../data/mock_balance_history_data.dart';
import '../models/balance_history_point.dart';
import '../models/balance_history_range.dart';

/// Data seam for the Account Balance screen's Balance History chart —
/// abstract so widget tests can inject a fake, matching the
/// `QuickHistoryDataSource`/`AccountBalanceService` injectable-service
/// convention.
///
/// Deliberately separate from `AccountBalanceService`: that seam is backed
/// by the live customer-details endpoint, while this one is currently mock/
/// demo-only (see `MockBalanceHistoryDataSource`'s doc comment) — keeping
/// them as distinct seams stops the mock series from ever being confused
/// with, or accidentally wired to, the live summary/credit figures.
abstract class BalanceHistoryDataSource {
  Future<List<BalanceHistoryPoint>> fetchBalanceHistory(
    BalanceHistoryRange range,
  );
}

/// Default [BalanceHistoryDataSource]: returns the deterministic
/// [kMockBalanceHistoryByRange] series with a simulated network delay.
///
/// NOT backed by Business Central. `customer-details?date_from/date_to`
/// returns an identical `customerBalance` for every range (only the echoed
/// `DateFilter` changes — confirmed by live testing on 2026-08-30), so no
/// genuine historical series is available from that endpoint yet. This
/// stays the default until a real historical API is confirmed.
class MockBalanceHistoryDataSource implements BalanceHistoryDataSource {
  const MockBalanceHistoryDataSource();

  @override
  Future<List<BalanceHistoryPoint>> fetchBalanceHistory(
    BalanceHistoryRange range,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return kMockBalanceHistoryByRange[range]!;
  }
}
