/// Formats [amount] with comma thousands separators and exactly two decimal
/// places, prefixed either by [currencyCode] (e.g. `"AED 1,936.50"`) when
/// supplied, or by a leading "$" (e.g. `12250` -> `"$12,250.00"`) when it is
/// `null` — the app's existing default for data with no known currency.
///
/// [currencyCode] is displayed exactly as given (e.g. an ISO 4217 code like
/// `"AED"` or `"USD"`) — never converted, exchanged, or re-derived; this
/// function only decides how to render an already-known currency, never
/// which one it is.
///
/// No currency-formatting helper existed anywhere in the app before this —
/// other screens (e.g. Order Detail's Price Breakdown) store amounts as
/// already pre-formatted display strings instead of raw numbers. The
/// Invoice line-items table needs real numeric values so line totals,
/// subtotal, tax, and the total amount can be calculated instead of
/// duplicated across widgets, so this is the one shared place that turns
/// those numbers into display text.
///
/// TODO: Replace with locale-aware formatting (e.g. via `package:intl`)
/// once the app's locale requirements are confirmed — this assumes
/// USD-style digit grouping regardless of [currencyCode].
String formatCurrency(num amount, {String? currencyCode}) {
  final isNegative = amount < 0;
  final grouped = _groupedTwoDecimals(amount.abs());

  final prefix = currencyCode == null ? '\$' : '$currencyCode ';
  return '${isNegative ? '-' : ''}$prefix$grouped';
}

/// Comma-grouped, two-decimal digits for a non-negative [amount] (e.g.
/// `12250.0` -> `"12,250.00"`) — the shared grouping/rounding logic behind
/// every currency-style formatter in this file. Never called with a
/// negative value; sign handling is each caller's own responsibility.
String _groupedTwoDecimals(num amount) {
  final fixed = amount.toStringAsFixed(2);
  final dotIndex = fixed.indexOf('.');
  final wholePart = fixed.substring(0, dotIndex);
  final decimalPart = fixed.substring(dotIndex + 1);

  final buffer = StringBuffer();
  for (var i = 0; i < wholePart.length; i++) {
    if (i > 0 && (wholePart.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(wholePart[i]);
  }
  return '$buffer.$decimalPart';
}

/// Formats [amount] the same two-decimal, thousands-grouped, signed-prefix
/// way as [formatCurrency], but for callers whose confirmed contract
/// forbids ever silently defaulting a missing currency to "$" — e.g.
/// Current Balance, whose live ledger-entries source may legitimately
/// return a blank `Currency_Code`.
///
/// [currencyCode] is displayed exactly as given, never converted or
/// re-derived — same as [formatCurrency]. When it is `null`, empty, or
/// whitespace-only, there is no prefix at all (e.g. `"42,850.00"`, same as
/// [formatPlainAmount]) — a guessed symbol would misrepresent the currency,
/// and per product decision (2026-09-03) an unknown currency is shown as
/// plainly as the amount itself, never flagged with a "?" marker.
String formatCurrencyOrUnknown(num amount, {required String? currencyCode}) {
  final isNegative = amount < 0;
  final grouped = _groupedTwoDecimals(amount.abs());

  final trimmedCode = currencyCode?.trim();
  final prefix = (trimmedCode == null || trimmedCode.isEmpty)
      ? ''
      : '$trimmedCode ';
  return '${isNegative ? '-' : ''}$prefix$grouped';
}

/// Formats [amount] with comma thousands separators and exactly two decimal
/// places, with no currency prefix at all (e.g. `180.0` -> `"180.00"`,
/// `1250.5` -> `"1,250.50"`).
///
/// For fields the API contract documents as plain numbers with no
/// associated currency (e.g. a sales-order line's `Quantity`/`Unit_Price`/
/// `Amount`) — unlike [formatCurrency]/[formatCurrencyOrUnknown], this never
/// prepends a guessed `"$"` or a `"?"` placeholder, since neither implies
/// this value is even denominated in a currency at all.
String formatPlainAmount(num amount) {
  final isNegative = amount < 0;
  final grouped = _groupedTwoDecimals(amount.abs());
  return '${isNegative ? '-' : ''}$grouped';
}

/// Formats [amount] as a signed, whole-dollar currency string for compact
/// transaction rows (e.g. `-2400` -> `"-$2,400"`, `15000` -> `"+$15,000"`).
///
/// Always shows an explicit `+`/`-` sign and no decimal places, unlike
/// [formatCurrency] — matches the Quick History design's transaction-amount
/// format, where whole-dollar figures with a clear credit/debit sign read
/// better than cents.
String formatSignedCurrency(num amount) {
  final isNegative = amount < 0;
  final whole = amount.abs().round().toString();

  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(whole[i]);
  }

  return '${isNegative ? '-' : '+'}\$$buffer';
}
