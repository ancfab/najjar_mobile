import '../data/mock_account_balance_data.dart';
import '../models/account_balance_summary.dart';
import '../models/balance_history_point.dart';
import '../models/balance_history_range.dart';
import '../models/credit_utilization_data.dart';

/// Data seam for the Account Balance screen: global balance summary, credit
/// utilization, and balance history by time range.
///
/// Quick History is deliberately not part of this seam — it is backed by
/// the live Business Central ledger-entries endpoint (see
/// `QuickHistoryDataSource`/`LedgerQuickHistoryDataSource`), not mock data.
///
/// TODO(api): Replace [MockAccountBalanceService] with a real API-backed
/// implementation once the backend endpoint and response contract are
/// confirmed. The screen depends on this abstract type (constructor-
/// injectable, defaulting to the mock) so that swap won't require changes
/// outside this file.
abstract class AccountBalanceService {
  Future<AccountBalanceSummary> fetchSummary();

  Future<CreditUtilizationData> fetchCreditUtilization();

  Future<List<BalanceHistoryPoint>> fetchBalanceHistory(
    BalanceHistoryRange range,
  );
}

/// Mock implementation returning deterministic sample data with a simulated
/// network delay, used until the real backend endpoints are confirmed.
class MockAccountBalanceService implements AccountBalanceService {
  const MockAccountBalanceService();

  @override
  Future<AccountBalanceSummary> fetchSummary() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return kMockAccountBalanceSummary;
  }

  @override
  Future<CreditUtilizationData> fetchCreditUtilization() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return kMockCreditUtilizationData;
  }

  @override
  Future<List<BalanceHistoryPoint>> fetchBalanceHistory(
    BalanceHistoryRange range,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return kMockBalanceHistoryByRange[range]!;
  }
}
