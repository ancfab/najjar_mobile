/// Credit figures shown in the Account Balance screen's Credit Utilization
/// card, sourced verbatim from the Business Central customer-details
/// endpoint's `availableCredit`/`usedCredit` fields.
///
/// Carries no backend-confirmed credit-limit/total field — the customer-
/// details endpoint doesn't return one — so [availableCreditRatio]/
/// [usedCreditRatio] are derived purely from these two live values
/// (`availableCredit + usedCredit` as the denominator) rather than from any
/// separate, invented credit-limit figure.
class CreditUtilizationData {
  const CreditUtilizationData({
    required this.availableCredit,
    required this.usedCredit,
  });

  final double availableCredit;
  final double usedCredit;

  /// Denominator for the progress bars below, derived solely from the two
  /// live figures this class holds — never a separate credit-limit value.
  double get _total => availableCredit + usedCredit;

  /// Fraction of ([availableCredit] + [usedCredit]) represented by
  /// [availableCredit], clamped to `0..1`.
  double get availableCreditRatio =>
      _total <= 0 ? 0.0 : (availableCredit / _total).clamp(0.0, 1.0).toDouble();

  /// Fraction of ([availableCredit] + [usedCredit]) represented by
  /// [usedCredit], clamped to `0..1`.
  double get usedCreditRatio =>
      _total <= 0 ? 0.0 : (usedCredit / _total).clamp(0.0, 1.0).toDouble();
}
