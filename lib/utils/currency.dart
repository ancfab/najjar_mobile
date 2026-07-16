/// Formats [amount] as a USD-style currency string with a leading "$",
/// comma thousands separators, and exactly two decimal places (e.g. `12250`
/// -> `"$12,250.00"`).
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
/// once the app's currency/locale requirements are confirmed — this
/// assumes USD-style grouping and a single currency symbol.
String formatCurrency(num amount) {
  final isNegative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
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

  return '${isNegative ? '-' : ''}\$$buffer.$decimalPart';
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
