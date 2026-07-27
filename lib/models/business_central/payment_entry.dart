/// Purpose: One row of the Business Central payments endpoint's paginated
/// response.
///
/// Responsibilities:
/// - Parse the exact camelCase backend keys this endpoint's API contract
///   defines (`entryNo`, `postingDate`, `documentNo`, `customerNo`,
///   `customerName`, `currencyCode`, `amount`, `remainingAmount`, `open`,
///   `dueDate`) — never the PascalCase_With_Underscores keys the ledger-
///   entries endpoint uses (`Entry_No`, `Posting_Date`, ...); Business
///   Central naming is inconsistent between endpoints, so this parser must
///   not accept those as aliases.
/// - Parse `amount`/`remainingAmount` as `double` whether the backend sends
///   an integer or a decimal, and `postingDate`/`dueDate` as strict
///   date-only (`yyyy-MM-dd`) values.
/// - Throw a [FormatException] — never an uncontrolled cast error, and
///   never a silently-applied fallback value — for any missing or
///   malformed required field.
///
/// Must not:
/// - Reuse `LedgerEntry.fromJson` — the two endpoints' field names differ.
/// - Assign a user-facing meaning to [isOpen], [remainingAmount], or
///   [dueDate] — this class is transport/domain parsing only.
/// - Expose [customerName], [amount], or [remainingAmount] through
///   [toString] — financial/customer-identifying fields are never logged
///   implicitly.
class PaymentEntry {
  const PaymentEntry({
    required this.entryNo,
    required this.postingDate,
    required this.documentNo,
    required this.customerNo,
    required this.customerName,
    required this.currencyCode,
    required this.amount,
    required this.remainingAmount,
    required this.dueDate,
    required this.isOpen,
  });

  final int entryNo;
  final DateTime postingDate;
  final String documentNo;
  final String customerNo;
  final String customerName;
  final String currencyCode;
  final double amount;
  final double remainingAmount;
  final DateTime dueDate;
  final bool isOpen;

  static final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  factory PaymentEntry.fromJson(Map<String, dynamic> json) {
    return PaymentEntry(
      entryNo: _requireInt(json, 'entryNo'),
      postingDate: _requireDateOnly(json, 'postingDate'),
      documentNo: _requireString(json, 'documentNo'),
      customerNo: _requireString(json, 'customerNo'),
      customerName: _requireString(json, 'customerName'),
      currencyCode: _requireString(json, 'currencyCode'),
      amount: _requireNum(json, 'amount'),
      remainingAmount: _requireNum(json, 'remainingAmount'),
      dueDate: _requireDateOnly(json, 'dueDate'),
      isOpen: _requireBool(json, 'open'),
    );
  }

  static int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('PaymentEntry.$key missing or not an int');
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException('PaymentEntry.$key missing or not a number');
  }

  /// Requires [key] to be present and a [String] — nothing more. The
  /// Payments contract documents JSON types only; it does not state that
  /// [documentNo]/[customerNo]/[customerName]/[currencyCode] must be
  /// non-empty, so this does not invent that constraint (unlike
  /// `LedgerEntry`, whose non-empty check is that model's own choice, not a
  /// contract requirement shared across Business Central endpoints — see
  /// e.g. `AuthSession.bcCustomerNo`, which is also only type-checked, not
  /// checked for emptiness). An empty string is passed through unmodified:
  /// never trimmed, never replaced, never rejected.
  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('PaymentEntry.$key missing or not a string');
    }
    return value;
  }

  static bool _requireBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException('PaymentEntry.$key missing or not a bool');
    }
    return value;
  }

  static DateTime _requireDateOnly(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || !_dateOnlyPattern.hasMatch(value)) {
      throw FormatException(
        'PaymentEntry.$key missing or not a yyyy-MM-dd date string',
      );
    }
    try {
      return DateTime.parse(value);
    } on FormatException {
      throw FormatException('PaymentEntry.$key was not a valid calendar date');
    }
  }

  /// Deliberately omits [customerName], [amount], and [remainingAmount] —
  /// see the class-level doc comment.
  @override
  String toString() =>
      'PaymentEntry(entryNo: $entryNo, documentNo: $documentNo)';
}
