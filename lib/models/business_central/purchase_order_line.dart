/// Purpose: One row of the Business Central purchase-orders endpoint's
/// paginated response — vendor-side procurement lines the stock check uses
/// to answer "is more stock already on order for this item, and when is it
/// expected to arrive?".
///
/// Responsibilities:
/// - Parse the canonical keys the ANC API normalizes every tenant's rows to
///   server-side: `Document_No`, `Line_No`, `No` (the Business Central item
///   number), `Description`, `Quantity` and `Expected_Receipt_Date`.
/// - Treat `Expected_Receipt_Date` as genuinely optional: a tenant page may
///   not publish any receipt-date field, and BC frequently leaves it blank
///   (`null`/`""`/`"0001-01-01"`). Absent/blank/sentinel values parse to
///   `null` — never a fabricated date.
/// - Be lenient about identity/quantity fields the way this feature needs
///   (a purchase-order line with a missing `Quantity` is still evidence of
///   incoming stock), unlike the strict sales/invoice line models: only a
///   missing/blank item `No` throws, since a row that can't be attributed
///   to an item is meaningless to every caller of this model.
///
/// Must not:
/// - Expose vendor or cost fields — the ANC API strips them server-side and
///   this model must never re-introduce them.
class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.itemNo,
    this.documentNo,
    this.lineNo,
    this.description,
    this.quantity,
    this.expectedReceiptDate,
  });

  /// Parsed from the canonical `No` key (the Business Central item number).
  /// Named `itemNo` rather than `no` to avoid a confusing, near-reserved-
  /// word Dart identifier — same convention as the other line models.
  final String itemNo;

  final String? documentNo;
  final int? lineNo;
  final String? description;
  final double? quantity;

  /// When this line's stock is expected to be received, or `null` when the
  /// row carries no usable date — see the class doc comment.
  final DateTime? expectedReceiptDate;

  static final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}');

  /// Business Central's "no date" sentinel.
  static const String _sentinelDate = '0001-01-01';

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> json) {
    final itemNo = json['No'];
    if (itemNo is! String || itemNo.trim().isEmpty) {
      throw const FormatException(
        'PurchaseOrderLine.No missing or not a non-empty string',
      );
    }

    return PurchaseOrderLine(
      itemNo: itemNo,
      documentNo: _optionalString(json, 'Document_No'),
      lineNo: _optionalInt(json, 'Line_No'),
      description: _optionalString(json, 'Description'),
      quantity: _optionalNum(json, 'Quantity'),
      expectedReceiptDate: _optionalDateOnly(json, 'Expected_Receipt_Date'),
    );
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) return null;
    return value;
  }

  static int? _optionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) return null;
    return value;
  }

  static double? _optionalNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return null;
  }

  /// Returns `null` for an absent key, JSON `null`, a non-String value, an
  /// empty string, BC's `0001-01-01` sentinel, or a string that doesn't
  /// start with `yyyy-MM-dd` — a malformed date on a procurement row must
  /// degrade to "no known date", never crash the stock-check flow.
  static DateTime? _optionalDateOnly(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) return null;
    if (value.startsWith(_sentinelDate)) return null;
    if (!_dateOnlyPattern.hasMatch(value)) return null;
    return DateTime.tryParse(value.substring(0, 10));
  }

  /// Deliberately omits every field except identity — same logging
  /// discipline as the other line models.
  @override
  String toString() =>
      'PurchaseOrderLine(documentNo: $documentNo, lineNo: $lineNo)';
}
