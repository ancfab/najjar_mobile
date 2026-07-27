// Fake AccountBalanceService for AccountBalanceScreen tests: resolves
// immediately (no simulated network delay) with deterministic mock data, so
// tests don't need to pump for an artificial delay.
//
// Quick History is intentionally not part of this fake — it is backed by a
// separate QuickHistoryDataSource seam (see fake_quick_history_data_source.dart).

import 'package:anc_fabrics/data/mock_account_balance_data.dart';
import 'package:anc_fabrics/models/account_balance_summary.dart';
import 'package:anc_fabrics/models/balance_history_point.dart';
import 'package:anc_fabrics/models/balance_history_range.dart';
import 'package:anc_fabrics/models/credit_utilization_data.dart';
import 'package:anc_fabrics/services/account_balance_service.dart';

class FakeAccountBalanceService implements AccountBalanceService {
  FakeAccountBalanceService({
    AccountBalanceSummary? summary,
    CreditUtilizationData? creditUtilization,
    Map<BalanceHistoryRange, List<BalanceHistoryPoint>>? historyByRange,
  }) : summary = summary ?? kMockAccountBalanceSummary,
       creditUtilization = creditUtilization ?? kMockCreditUtilizationData,
       historyByRange = historyByRange ?? kMockBalanceHistoryByRange;

  final AccountBalanceSummary summary;
  final CreditUtilizationData creditUtilization;
  final Map<BalanceHistoryRange, List<BalanceHistoryPoint>> historyByRange;

  @override
  Future<AccountBalanceSummary> fetchSummary() async => summary;

  @override
  Future<CreditUtilizationData> fetchCreditUtilization() async =>
      creditUtilization;

  @override
  Future<List<BalanceHistoryPoint>> fetchBalanceHistory(
    BalanceHistoryRange range,
  ) async => historyByRange[range]!;
}
