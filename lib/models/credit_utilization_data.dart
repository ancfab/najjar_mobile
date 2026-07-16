/// Credit utilization figures shown in the Account Balance screen's Credit
/// Utilization card.
///
// TODO(api): Replace mock account-balance summary and credit-utilization
// data after the backend endpoint and response contract are confirmed.
class CreditUtilizationData {
  const CreditUtilizationData({
    required this.totalCredit,
    required this.availableCredit,
    required this.usedCredit,
    this.creditLimitChangeNote,
  });

  final double totalCredit;
  final double availableCredit;
  final double usedCredit;

  /// Freeform note about a recent credit limit change (e.g. "Your credit
  /// limit was recently increased by $10,000 on Oct 12."), or null/empty to
  /// render nothing — matches `InvoiceNotesSection`'s convention of omitting
  /// optional freeform fields entirely rather than showing a placeholder.
  final String? creditLimitChangeNote;

  /// Fraction of [totalCredit] represented by [availableCredit], clamped to
  /// `0..1` so the progress bar is calculated from the supplied values
  /// rather than an arbitrary hardcoded width.
  double get availableCreditRatio => totalCredit <= 0
      ? 0.0
      : (availableCredit / totalCredit).clamp(0.0, 1.0).toDouble();

  /// Fraction of [totalCredit] represented by [usedCredit], clamped to
  /// `0..1` so the progress bar is calculated from the supplied values
  /// rather than an arbitrary hardcoded width.
  double get usedCreditRatio => totalCredit <= 0
      ? 0.0
      : (usedCredit / totalCredit).clamp(0.0, 1.0).toDouble();
}
