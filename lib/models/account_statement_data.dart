import 'account_transaction.dart';
import 'credit_utilization_data.dart';

/// Snapshot of currently available Account Balance screen data, assembled
/// when Export PDF is tapped so the generated statement reflects exactly
/// what's on screen at that moment (the global balance, credit utilization,
/// the selected Balance History From/To range, and live Quick History
/// transactions).
class AccountStatementData {
  const AccountStatementData({
    required this.customerBalance,
    required this.creditUtilization,
    required this.historyFrom,
    required this.historyTo,
    this.quickHistory = const [],
    required this.generatedAt,
    this.currencyCode,
  });

  /// The Global Account Balance hero figure (`customerBalance` from the
  /// no-date-filter customer-details snapshot).
  final double customerBalance;

  final CreditUtilizationData creditUtilization;

  /// The Balance History From/To range selected on screen when export was
  /// tapped — included as a label only (e.g. "Oct 1, 2023 - Oct 30, 2023");
  /// Balance History's own (real, ledger-derived) transaction rows are not
  /// duplicated into the statement — only Quick History's rows are, per the
  /// existing [quickHistory] field.
  final DateTime historyFrom;
  final DateTime historyTo;

  /// Live Quick History rows (from `LedgerQuickHistoryDataSource`) shown on
  /// screen at export time.
  final List<AccountTransaction> quickHistory;

  /// When the statement was generated, shown on the document itself.
  final DateTime generatedAt;

  /// The display currency for [customerBalance] and [creditUtilization]'s
  /// figures — Home's already-loaded `CurrentBalanceAmount.currencyCode`
  /// (ultimately ledger-entries' `Currency_Code`), passed straight through
  /// by `AccountBalanceScreen`. Never derived from `customer-details`
  /// itself, which exposes no currency field, and never re-resolved here.
  /// `null` when not yet resolved, in which case every amount renders
  /// through `formatCurrencyOrUnknown`'s "?" fallback rather than a guessed
  /// code.
  final String? currencyCode;
}
