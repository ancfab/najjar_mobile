/// One point on the Account Balance screen's Balance History graph: the
/// customer's real account balance immediately after [date]'s ledger
/// activity (or the opening balance at the start of the selected range —
/// see `LedgerBalanceHistoryDataSource`'s doc comment for exactly which).
///
/// Calculated, not fabricated: derived entirely from real fetched
/// [LedgerEntry] rows and the existing, confirmed `computeCurrentBalance`
/// anchor — see `LedgerBalanceHistoryDataSource.fetchBalanceHistory` for the
/// exact reconstruction formula. This class carries no defaults and no
/// generated/random values; every instance is produced by that
/// reconstruction from a real fetch.
class BalanceHistoryPoint {
  const BalanceHistoryPoint({
    required this.date,
    required this.balance,
    required this.currencyCode,
  });

  final DateTime date;
  final double balance;

  /// The single currency all contributing entries shared, or `null` when
  /// every contributing entry had a blank `Currency_Code`. Never a guessed
  /// or region-inferred code — see
  /// `LedgerBalanceHistoryDataSource.fetchBalanceHistory`'s currency-
  /// consistency check, which prevents a point from ever being produced when
  /// more than one distinct currency is present.
  final String? currencyCode;
}
