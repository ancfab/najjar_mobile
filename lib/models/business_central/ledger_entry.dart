/// Purpose: One row of the Business Central ledger-entries endpoint's
/// paginated response.
///
/// Responsibilities:
/// - Parse the exact PascalCase_With_Underscores backend keys this
///   endpoint's API contract defines — never a camelCase or snake_case
///   variant of them.
/// - Parse `Amount`/`Remaining_Amount` as `double` whether the backend sends
///   an integer or a decimal, and `Posting_Date`/`Due_Date` as strict
///   date-only (`yyyy-MM-dd`) values.
/// - Throw a [FormatException] — never an uncontrolled cast error — for any
///   missing or malformed required field.
///
/// Must not:
/// - Interpret whether a positive or negative [amount] means a credit or a
///   debit — that convention is not defined by this endpoint's contract
///   (see `LedgerEntryPresentationAdapter`, which deliberately renders a
///   neutral presentation rather than guessing).
/// - Expose [customerName], [amount], or [remainingAmount] through
///   [toString] — financial/customer-identifying fields are never logged
///   implicitly.
class LedgerEntry {
  const LedgerEntry({
    required this.entryNo,
    required this.postingDate,
    required this.documentType,
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
  final String documentType;
  final String documentNo;
  final String customerNo;
  final String customerName;
  final String currencyCode;
  final double amount;
  final double remainingAmount;
  final DateTime dueDate;
  final bool isOpen;

  static final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      entryNo: _requireInt(json, 'Entry_No'),
      postingDate: _requireDateOnly(json, 'Posting_Date'),
      documentType: _requireString(json, 'Document_Type'),
      documentNo: _requireString(json, 'Document_No'),
      customerNo: _requireString(json, 'Customer_No'),
      customerName: _requireString(json, 'Customer_Name'),
      currencyCode: _requireString(json, 'Currency_Code'),
      amount: _requireNum(json, 'Amount'),
      remainingAmount: _requireNum(json, 'Remaining_Amount'),
      dueDate: _requireDateOnly(json, 'Due_Date'),
      isOpen: _requireBool(json, 'Open'),
    );
  }

  static int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('LedgerEntry.$key missing or not an int');
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException('LedgerEntry.$key missing or not a number');
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'LedgerEntry.$key missing or not a non-empty string',
      );
    }
    return value;
  }

  static bool _requireBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException('LedgerEntry.$key missing or not a bool');
    }
    return value;
  }

  static DateTime _requireDateOnly(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || !_dateOnlyPattern.hasMatch(value)) {
      throw FormatException(
        'LedgerEntry.$key missing or not a yyyy-MM-dd date string',
      );
    }
    try {
      return DateTime.parse(value);
    } on FormatException {
      throw FormatException('LedgerEntry.$key was not a valid calendar date');
    }
  }

  /// Deliberately omits [customerName], [amount], and [remainingAmount] —
  /// see the class-level doc comment.
  @override
  String toString() =>
      'LedgerEntry(entryNo: $entryNo, documentType: $documentType, '
      'documentNo: $documentNo)';
}
