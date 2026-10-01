import '../services/current_balance_service.dart';

/// Purpose: One account's most recently *computed* Current Balance, kept
/// locally so the Home card can show a figure the instant the screen opens
/// instead of leaving the user watching a spinner while every ledger page
/// is fetched.
///
/// Responsibilities:
/// - Carry the computed [CurrentBalanceAmount] exactly as
///   `computeCurrentBalance` produced it — including a `null`
///   `currencyCode`, which stays `null` rather than becoming a guessed
///   currency on the way through storage.
/// - Carry [cachedAt] so the UI can tell the user it is showing a saved
///   figure rather than a freshly confirmed one.
///
/// Must not:
/// - Be treated as authoritative. A cached figure is a display convenience
///   shown while (or after a failed attempt at) a live refresh — the live
///   ledger sweep remains the only thing that confirms a balance.
/// - Be used for the Business Central `CustomerDetails` balance/credit
///   figures behind the Account Balance screen; that endpoint's contract
///   requires a fresh, never-cached fetch (see
///   `LocalCustomerProfileStore`'s doc comment).
class CachedCurrentBalance {
  const CachedCurrentBalance({required this.amount, required this.cachedAt});

  final CurrentBalanceAmount amount;

  /// When [amount] was computed from a live ledger sweep, in UTC.
  final DateTime cachedAt;

  /// Parses a stored envelope, or returns `null` for anything unreadable —
  /// a missing/!num amount, a missing/unparseable timestamp, or a
  /// present-but-non-String currency code. A corrupt cache entry is never
  /// repaired by guessing: the caller simply treats it as "nothing cached".
  static CachedCurrentBalance? fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    if (amount is! num) return null;

    final rawCachedAt = json['cachedAt'];
    if (rawCachedAt is! String) return null;
    final cachedAt = DateTime.tryParse(rawCachedAt);
    if (cachedAt == null) return null;

    final rawCurrencyCode = json['currencyCode'];
    if (rawCurrencyCode != null && rawCurrencyCode is! String) return null;

    return CachedCurrentBalance(
      amount: CurrentBalanceAmount(
        amount: amount.toDouble(),
        currencyCode: rawCurrencyCode as String?,
      ),
      cachedAt: cachedAt.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'amount': amount.amount,
    'currencyCode': amount.currencyCode,
    'cachedAt': cachedAt.toUtc().toIso8601String(),
  };

  /// Deliberately omits the amount — financial data is never logged
  /// implicitly, matching `LedgerEntry`/`CustomerDetails`' convention.
  @override
  String toString() => 'CachedCurrentBalance(cachedAt: $cachedAt)';
}
