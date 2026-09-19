/// Purpose: One row of the Business Central Zebra sales-orders endpoint's
/// paginated response.
///
/// Responsibilities:
/// - Parse the same canonical PascalCase_With_Underscores keys as
///   [BusinessCentralSalesOrderLine] for the fields the two endpoints share
///   (confirmed live: a Zebra order's lines carry identical item/quantity/
///   amount values to the same order's plain Sales Order rows) — including
///   the literal `No.` key (with a trailing period) for the item number.
/// - ADDITIONALLY parse this endpoint's own raw fields, never normalized
///   server-side because they have no equivalent on the plain Sales Order
///   page: [orderId] (the order-level GUID, confirmed equal to the plain
///   Sales Order page's own `documentId` for the same order — this is what
///   lets `OrderDetailScreen` look up a Zebra order's detail using the
///   identifier the plain Sales Order list already has), [status],
///   [salespersonCode], [memo], [currencyCode], [orderDate], and the
///   per-line cut-to-size dimensions [width]/[length]/[sqMtr].
/// - Represent one order line, not one complete order: many rows share one
///   [documentNo]/[orderId] (including non-item lines like a delivery
///   charge) — grouping lines into a complete order is out of scope for
///   this model, same as [BusinessCentralSalesOrderLine].
/// - Throw a [FormatException] — never an uncontrolled cast error, and
///   never a silently-applied fallback value — for any missing or
///   malformed required field, in particular the identity fields
///   `Document_No`/`Line_No`/`orderId`.
///
/// Must not:
/// - Group rows by [documentNo]/[orderId], or assign any order-summary
///   meaning (a computed total, a delivery ETA) beyond passing through the
///   fields this contract documents.
/// - Expose [sellToCustomerName], [unitPrice], [amount], or [memo] through
///   [toString] — financial/customer-identifying/free-text fields are never
///   logged implicitly, same restraint as [BusinessCentralSalesOrderLine].
class BusinessCentralZebraSalesOrderLine {
  const BusinessCentralZebraSalesOrderLine({
    required this.documentNo,
    required this.lineNo,
    required this.orderId,
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
    this.status,
    this.salespersonCode,
    this.memo,
    this.currencyCode,
    this.orderDate,
    this.width,
    this.length,
    this.sqMtr,
  });

  final String documentNo;
  final int lineNo;

  /// The order-level GUID this line belongs to — confirmed equal to the
  /// plain Sales Order page's own `documentId` for the same order. Required
  /// (never null/blank): every real Zebra row carries it, and
  /// `ZebraOrderDetailService` depends on it to defensively confirm a
  /// returned row actually belongs to the order that was asked for (see
  /// that class's doc comment), the same defensive role [documentNo] plays
  /// for `OrderDetailService`.
  final String orderId;

  final String sellToCustomerNo;
  final String sellToCustomerName;

  /// Parsed from the contract's `No.` key (the Business Central item
  /// number, with a literal trailing period). Named `itemNo` rather than
  /// `no` to avoid a confusing, near-reserved-word Dart identifier — same
  /// as [BusinessCentralSalesOrderLine.itemNo].
  final String itemNo;

  final String description;
  final double quantity;
  final double unitPrice;
  final double amount;

  final String? unitOfMeasureCode;
  final double? discountPercent;
  final double? discountAmount;
  final double? amountIncludingTax;
  final DateTime? shipmentDate;

  /// The order's raw Business Central status (e.g. `"Open"`, `"Released"`)
  /// — deliberately NOT mapped onto [OrderStatus]/`mapOrderStatus`, whose
  /// values (`delivered`/`shipped`/`processing`) come from a different,
  /// unrelated mock taxonomy with no confirmed relationship to Zebra's real
  /// status values. Shown as-is (or omitted when absent), never translated
  /// or reinterpreted. `null` when absent/blank.
  final String? status;

  /// Parsed from `salespersonCode` when present and non-empty; `null`
  /// otherwise.
  final String? salespersonCode;

  /// Free-text order note. Parsed from `memo` when present and non-empty;
  /// `null` otherwise. Never shown in [toString] (see the class doc
  /// comment) — may contain customer-specific delivery instructions.
  final String? memo;

  /// Parsed from `currencyCode` when present and non-empty; `null`
  /// otherwise.
  final String? currencyCode;

  /// The order's placement date, parsed the same strict date-only way as
  /// [shipmentDate] (including BC's `0001-01-01` "no date" sentinel
  /// degrading to `null`, never a fabricated date).
  final DateTime? orderDate;

  /// Cut-to-size dimensions in meters, when this line represents a fabric
  /// cut rather than a flat-quantity item (e.g. a delivery-charge line has
  /// none of these, or reports zero) — `null` when absent, and also `null`
  /// when present but exactly zero, since BC reports zero for every
  /// non-fabric line rather than omitting the field, and a zero dimension
  /// is never meaningful to show.
  final double? width;
  final double? length;
  final double? sqMtr;

  /// The stable unique identity of one list item, per the same convention
  /// as [BusinessCentralSalesOrderLine.identity]: `Document_No` plus
  /// `Line_No`, joined with a single space. `Document_No` alone is not a
  /// unique row identity, since many lines share it.
  String get identity => '$documentNo $lineNo';

  /// Whether this line has a non-zero cut-to-size dimension worth showing.
  bool get hasDimensions =>
      (width ?? 0) > 0 || (length ?? 0) > 0 || (sqMtr ?? 0) > 0;

  static final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}');
  static const String _sentinelDate = '0001-01-01';

  factory BusinessCentralZebraSalesOrderLine.fromJson(
    Map<String, dynamic> json,
  ) {
    return BusinessCentralZebraSalesOrderLine(
      documentNo: _requireString(json, 'Document_No'),
      lineNo: _requireInt(json, 'Line_No'),
      orderId: _requireString(json, 'orderId'),
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
      status: _optionalNonEmptyString(json, 'status'),
      salespersonCode: _optionalNonEmptyString(json, 'salespersonCode'),
      memo: _optionalNonEmptyString(json, 'memo'),
      currencyCode: _optionalNonEmptyString(json, 'currencyCode'),
      orderDate: _optionalDateOnly(json, 'orderDate'),
      width: _optionalPositiveNum(json, 'width'),
      length: _optionalPositiveNum(json, 'length'),
      sqMtr: _optionalPositiveNum(json, 'sqMtr'),
    );
  }

  static int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException(
        'BusinessCentralZebraSalesOrderLine.$key missing or not an int',
      );
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'BusinessCentralZebraSalesOrderLine.$key missing or not a number',
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
      'BusinessCentralZebraSalesOrderLine.$key was present but not a number',
    );
  }

  /// Same as [_optionalNum], but a present zero (or negative — never
  /// expected, but never trusted either) collapses to `null` — see
  /// [width]/[length]/[sqMtr]'s doc comment for why zero is never shown.
  static double? _optionalPositiveNum(Map<String, dynamic> json, String key) {
    final value = _optionalNum(json, key);
    return (value == null || value <= 0) ? null : value;
  }

  /// Returns `null` when [key] is absent, explicitly `null`, an empty
  /// string, or (for whitespace-only Zebra text fields like `memo`) blank
  /// after trimming. A present non-blank value must be a [String]; any
  /// other present value (wrong type) throws [FormatException].
  static String? _optionalNonEmptyString(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException(
        'BusinessCentralZebraSalesOrderLine.$key present but not a string',
      );
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Returns `null` for an absent key, JSON `null`, a non-String value, an
  /// empty string, or BC's `0001-01-01` sentinel — never a fabricated date.
  /// A present value that starts with a valid `yyyy-MM-dd` prefix but still
  /// fails to parse throws, same as [BusinessCentralSalesOrderLine]'s
  /// equivalent helper.
  static DateTime? _optionalDateOnly(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) return null;
    if (value.startsWith(_sentinelDate)) return null;
    if (!_dateOnlyPattern.hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value.substring(0, 10));
    if (parsed == null) {
      throw FormatException(
        'BusinessCentralZebraSalesOrderLine.$key was not a valid calendar '
        'date',
      );
    }
    return parsed;
  }

  /// Requires [key] to be present and a non-empty [String] — same
  /// non-empty check as [BusinessCentralSalesOrderLine]'s equivalent
  /// helper, applied to every required string field here.
  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'BusinessCentralZebraSalesOrderLine.$key missing or not a non-empty '
        'string',
      );
    }
    return value;
  }

  /// Deliberately omits every other field — see the class-level doc
  /// comment.
  @override
  String toString() =>
      'BusinessCentralZebraSalesOrderLine(documentNo: $documentNo, '
      'lineNo: $lineNo)';
}
