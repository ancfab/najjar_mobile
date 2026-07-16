/// Time-range options for the Balance History chart's segmented selector.
enum BalanceHistoryRange { thirtyDays, ninetyDays, oneYear }

extension BalanceHistoryRangeLabel on BalanceHistoryRange {
  /// Display label matching the segmented selector's button text exactly
  /// (e.g. `"30 Days"`).
  String get label {
    switch (this) {
      case BalanceHistoryRange.thirtyDays:
        return '30 Days';
      case BalanceHistoryRange.ninetyDays:
        return '90 Days';
      case BalanceHistoryRange.oneYear:
        return '1 Year';
    }
  }
}
