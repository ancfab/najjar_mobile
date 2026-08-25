/// Global account balance summary shown in the Account Balance screen's
/// hero card.
///
// data after the backend endpoint and response contract are confirmed.
class AccountBalanceSummary {
  const AccountBalanceSummary({
    required this.currentBalance,
    required this.percentChangeFromLastMonth,
    required this.changePeriodLabel,
  });

  /// Current global account balance, e.g. `42850.00`.
  final double currentBalance;

  /// Percentage change vs. the prior period, e.g. `12.4` for "+12.4%".
  /// A negative value renders with a downward-trend icon instead.
  final double percentChangeFromLastMonth;

  /// Trailing label shown after the percentage, e.g. "from last month".
  final String changePeriodLabel;
}
