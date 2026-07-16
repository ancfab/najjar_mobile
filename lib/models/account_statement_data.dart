import 'account_balance_summary.dart';
import 'account_transaction.dart';
import 'balance_history_range.dart';
import 'credit_utilization_data.dart';

/// Snapshot of currently available Account Balance screen data, assembled
/// when Export PDF is tapped so the generated statement reflects exactly
/// what's on screen at that moment (the global balance, credit utilization,
/// the selected Balance History range, and Quick History transactions).
class AccountStatementData {
  const AccountStatementData({
    required this.summary,
    required this.creditUtilization,
    required this.selectedRange,
    required this.quickHistory,
    required this.generatedAt,
  });

  final AccountBalanceSummary summary;
  final CreditUtilizationData creditUtilization;
  final BalanceHistoryRange selectedRange;
  final List<AccountTransaction> quickHistory;

  /// When the statement was generated, shown on the document itself.
  final DateTime generatedAt;
}
