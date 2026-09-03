/// Purpose: One row of the Business Central sales-orders endpoint's
/// paginated response.
///
/// Responsibilities:
/// - Parse the exact PascalCase_With_Underscores backend keys this
///   endpoint's confirmed contract defines — including the literal `No.`
///   key (with a trailing period) for the Business Central item number,
///   never a normalized `No` variant.
/// - Represent one sales-order line, not one distinct order: the same
///   `Document_No` can appear on many rows (one per line) — grouping lines
///   into a complete order is explicitly out of scope for this model.
/// - Parse `Quantity`/`Unit_Price`/`Amount` as `double` whether the backend
///   sends an integer or a decimal; `Line_Discount_Percent`/
///   `Line_Discount_Amount`/`Amount_Including_Tax` the same way when present
///   — all optional, see their doc comments.
/// - Throw a [FormatException] — never an uncontrolled cast error, and
///   never a silently-applied fallback value — for any missing or
///   malformed required field, in particular the identity fields
///   `Document_No`/`Line_No`.
///
/// Must not:
/// - Group rows by [documentNo], or assign any order-level meaning (status,
///   currency, or delivery state) to its fields — this class is flat
///   transport/domain parsing only, one row at a time, over exactly the
///   fields this contract documents. There is still no order-level status
///   field on this endpoint (confirmed 2026-09-03 alongside the fields
///   this update adds) — never invent one.
/// - Expose [sellToCustomerName], [unitPrice], or [amount] through
///   [toString] — financial/customer-identifying fields are never logged
///   implicitly.
class BusinessCentralSalesOrderLine {
  const BusinessCentralSalesOrderLine({
    required this.documentNo,
    required this.lineNo,
    required this.sellToCustomerNo,
    required this.sellToCustomerName,
    required this.itemNo,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    this.unitOfMeasureCode,
    this.discountPercent,
    this.discountAmount,
    this.amountIncludingTax,
    this.shipmentDate,
  });

  final String documentNo;
  final int lineNo;
  final String sellToCustomerNo;
  final String sellToCustomerName;

  /// Parsed from the contract's `No.` key (the Business Central item
  /// number, with a literal trailing period). Named `itemNo` rather than
  /// `no` to avoid a confusing, near-reserved-word Dart identifier.
  final String itemNo;

  final String description;
  final double quantity;
  final double unitPrice;
  final double amount;

  /// Parsed from `Unit_of_Measure_Code` when present (e.g. `"MT"`) — `null`
  /// when missing/blank/`null`. Confirmed live 2026-09-03 on Oman's real
  /// Sales Order page; not part of the originally documented contract, so
  /// never required.
  final String? unitOfMeasureCode;

  /// Parsed from `Line_Discount_Percent` when present and a number; `null`
  /// otherwise. A present-but-non-numeric value throws — same tolerance
  /// rule as every other optional numeric field in this app.
  final double? discountPercent;

  /// Parsed from `Line_Discount_Amount` when present and a number; `null`
  /// otherwise.
  final double? discountAmount;

  /// Parsed from `Amount_Including_Tax` when present and a number; `null`
  /// otherwise. BC's own field name on this page says "Tax", not "VAT" —
  /// deliberately not reused/conflated with
  /// `BusinessCentralInvoiceLine.amountIncludingVat`, a different page's
  /// field with no confirmed relationship to this one.
  final double? amountIncludingTax;

  /// Parsed from `Shipment_Date` as a strict date-only (`yyyy-MM-dd`) value
  /// when present; `null` when missing, blank, `null`, or BC's
  /// `0001-01-01` "no date" sentinel — never a fabricated date. A present
  /// value that is none of those but still fails to parse as a valid
  /// calendar date still throws — only genuine "no date" shapes degrade to
  /// `null`.
  final DateTime? shipmentDate;

  /// The stable unique identity of one list item, per the confirmed UX
  /// rule: `Document_No` plus `Line_No`, joined with a single space.
  /// `Document_No` alone is not a unique row identity, since many lines
  /// share it.
  String get identity => '$documentNo $lineNo';

  static final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}');
  static const String _sentinelDate = '0001-01-01';

  factory BusinessCentralSalesOrderLine.fromJson(Map<String, dynamic> json) {
    return BusinessCentralSalesOrderLine(
      documentNo: _requireString(json, 'Document_No'),
      lineNo: _requireInt(json, 'Line_No'),
      sellToCustomerNo: _requireString(json, 'Sell_to_Customer_No'),
      sellToCustomerName: _requireString(json, 'Sell_to_Customer_Name'),
      itemNo: _requireString(json, 'No.'),
      description: _requireString(json, 'Description'),
      quantity: _requireNum(json, 'Quantity'),
      unitPrice: _requireNum(json, 'Unit_Price'),
      amount: _requireNum(json, 'Amount'),
      unitOfMeasureCode: _optionalNonEmptyString(json, 'Unit_of_Measure_Code'),
      discountPercent: _optionalNum(json, 'Line_Discount_Percent'),
      discountAmount: _optionalNum(json, 'Line_Discount_Amount'),
      amountIncludingTax: _optionalNum(json, 'Amount_Including_Tax'),
      shipmentDate: _optionalDateOnly(json, 'Shipment_Date'),
    );
  }

  static int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException(
        'BusinessCentralSalesOrderLine.$key missing or not an int',
      );
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'BusinessCentralSalesOrderLine.$key missing or not a number',
    );
  }

  /// Returns `null` when [key] is absent or explicitly JSON `null`. A
  /// present value must still be a number; any other present value (wrong
  /// type) throws [FormatException].
  static double? _optionalNum(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'BusinessCentralSalesOrderLine.$key was present but not a number',
    );
  }

  /// Returns `null` when [key] is absent, explicitly `null`, or an empty
  /// string. A present non-blank value must be a [String]; any other
  /// present value (wrong type) throws [FormatException].
  static String? _optionalNonEmptyString(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException(
        'BusinessCentralSalesOrderLine.$key present but not a string',
      );
    }
    return value.isEmpty ? null : value;
  }

  /// Returns `null` for an absent key, JSON `null`, a non-String value, an
  /// empty string, or BC's `0001-01-01` sentinel — never a fabricated date.
  /// A present value that starts with a valid `yyyy-MM-dd` prefix but still
  /// fails to parse throws, same as every other strict date field in this
  /// app.
  static DateTime? _optionalDateOnly(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) return null;
    if (value.startsWith(_sentinelDate)) return null;
    if (!_dateOnlyPattern.hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value.substring(0, 10));
    if (parsed == null) {
      throw FormatException(
        'BusinessCentralSalesOrderLine.$key was not a valid calendar date',
      );
    }
    return parsed;
  }

  /// Requires [key] to be present and a non-empty [String] — `Document_No`
  /// and `Line_No` are this row's unique identity and must never be
  /// silently accepted as blank; the same non-empty check is applied to
  /// every other required string field here rather than carving out a
  /// separate, more permissive path for them.
  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'BusinessCentralSalesOrderLine.$key missing or not a non-empty '
        'string',
      );
    }
    return value;
  }

  /// Deliberately omits every other field — see the class-level doc
  /// comment.
  @override
  String toString() =>
      'BusinessCentralSalesOrderLine(documentNo: $documentNo, '
      'lineNo: $lineNo)';
}
