// Fake AccountBalanceService for AccountBalanceScreen tests: resolves
// immediately (no simulated network delay) with deterministic mock data, so
// tests don't need to pump for an artificial delay.

import 'package:anc_fabrics/data/mock_account_balance_data.dart';
import 'package:anc_fabrics/models/account_balance_summary.dart';
import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/models/balance_history_point.dart';
import 'package:anc_fabrics/models/balance_history_range.dart';
import 'package:anc_fabrics/models/credit_utilization_data.dart';
import 'package:anc_fabrics/services/account_balance_service.dart';

class FakeAccountBalanceService implements AccountBalanceService {
  FakeAccountBalanceService({
    AccountBalanceSummary? summary,
    CreditUtilizationData? creditUtilization,
    Map<BalanceHistoryRange, List<BalanceHistoryPoint>>? historyByRange,
    List<AccountTransaction>? quickHistory,
  }) : summary = summary ?? kMockAccountBalanceSummary,
       creditUtilization = creditUtilization ?? kMockCreditUtilizationData,
       historyByRange = historyByRange ?? kMockBalanceHistoryByRange,
       quickHistory = quickHistory ?? kMockQuickHistoryTransactions;

  final AccountBalanceSummary summary;
  final CreditUtilizationData creditUtilization;
  final Map<BalanceHistoryRange, List<BalanceHistoryPoint>> historyByRange;
  final List<AccountTransaction> quickHistory;

  @override
  Future<AccountBalanceSummary> fetchSummary() async => summary;

  @override
  Future<CreditUtilizationData> fetchCreditUtilization() async =>
      creditUtilization;

  @override
  Future<List<BalanceHistoryPoint>> fetchBalanceHistory(
    BalanceHistoryRange range,
  ) async => historyByRange[range]!;

  @override
  Future<List<AccountTransaction>> fetchQuickHistory() async => quickHistory;
}
