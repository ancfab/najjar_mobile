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
///   sends an integer or a decimal.
/// - Throw a [FormatException] — never an uncontrolled cast error, and
///   never a silently-applied fallback value — for any missing or
///   malformed required field, in particular the identity fields
///   `Document_No`/`Line_No`.
///
/// Must not:
/// - Group rows by [documentNo], or assign any order-level meaning (status,
///   date, fabric type, currency, delivery state, or a computed total) to
///   its fields — this class is flat transport/domain parsing only, one row
///   at a time, over exactly the fields this contract documents.
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

  /// The stable unique identity of one list item, per the confirmed UX
  /// rule: `Document_No` plus `Line_No`, joined with a single space.
  /// `Document_No` alone is not a unique row identity, since many lines
  /// share it.
  String get identity => '$documentNo $lineNo';

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
