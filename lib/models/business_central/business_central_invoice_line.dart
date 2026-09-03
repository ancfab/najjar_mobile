/// Purpose: One row of the Business Central invoices endpoint's paginated
/// response.
///
/// Responsibilities:
/// - Parse the exact PascalCase_With_Underscores backend keys this
///   endpoint's approved mobile contract defines — never a camelCase
///   (Payments-style) or otherwise-cased variant of them.
/// - Represent one invoice *line*, not a complete invoice: the same
///   `Document_No` can appear on many rows, across many pages (confirmed
///   live: a document's lines have been observed split across a page
///   boundary) — grouping lines into a complete invoice is explicitly out of
///   scope for this model/class.
/// - Parse `Quantity`/`Unit_Price`/`Amount` as `double` whether the backend
///   sends an integer or a decimal; `Amount_Including_VAT` the same way when
///   present — see [amountIncludingVat]'s doc comment for why it's nullable.
/// - Parse `Posting_Date` as an optional strict date-only (`yyyy-MM-dd`)
///   value — see [postingDate]'s doc comment for why this field is nullable
///   despite being listed as a required contract field.
/// - Parse `Currency_Code` as a "blankable" field (never `null` itself) —
///   see [currencyCode]'s doc comment.
/// - Ignore every undocumented/extra key the live response also returns
///   (e.g. `@odata.etag`, `Unit_Cost_LCY`, `Job_No`) — this class only ever
///   reads its own approved keys, so extra keys never cause a parse failure
///   and are never retained.
/// - Throw a [FormatException] — never an uncontrolled cast error, and
///   never a silently-applied fallback value — for any missing or malformed
///   required field.
///
/// Must not:
/// - Model, store, expose, log, or otherwise surface `Unit_Cost_LCY` or any
///   other undocumented/internal-cost field — those are not part of the
///   approved mobile contract.
/// - Reuse `PaymentEntry.fromJson` (camelCase keys) or `LedgerEntry.fromJson`
///   (a different PascalCase_With_Underscores contract) — each Business
///   Central endpoint's field names/casing are independent contracts.
/// - Group rows by [documentNo], calculate a subtotal/VAT/total, or assign
///   any invoice-level meaning to its fields — this class is flat
///   transport/domain parsing only, one row at a time.
/// - Expose [sellToCustomerNo], [sellToCustomerName], [amount],
///   [amountIncludingVat], or [unitPrice] through [toString] —
///   financial/customer-identifying fields are never logged implicitly.
class BusinessCentralInvoiceLine {
  const BusinessCentralInvoiceLine({
    required this.documentNo,
    required this.lineNo,
    required this.postingDate,
    required this.sellToCustomerNo,
    required this.sellToCustomerName,
    required this.type,
    required this.itemNo,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    this.amountIncludingVat,
    required this.orderNo,
    required this.currencyCode,
    this.invoiceStatus,
    this.dueDate,
    this.paymentMethod,
    this.estimatedDeliveryDate,
  });

  final String documentNo;
  final int lineNo;

  /// Parsed from `Posting_Date` when present and a valid `yyyy-MM-dd`
  /// string; `null` when the key is missing or explicitly `null`.
  ///
  /// The written API contract lists `Posting_Date` as present on every row,
  /// but the confirmed live deployment omits it (absent or `null`) on every
  /// row of page 1 — a confirmed mismatch between the documented contract
  /// and the deployed ANC API, not a mobile-side assumption. This field is
  /// nullable *only* because of that confirmed deployed behavior; it must
  /// never be defaulted to `DateTime.now()` or any other substitute date. A
  /// *present but malformed or non-String* value is still treated as a
  /// contract violation and throws [FormatException] — only a missing key
  /// or an explicit JSON `null` is tolerated as "unknown".
  final DateTime? postingDate;

  final String sellToCustomerNo;
  final String sellToCustomerName;
  final String type;

  /// Parsed from the contract's `No` key (the Business Central item
  /// number). Named `itemNo` rather than `no` to avoid a confusing,
  /// near-reserved-word Dart identifier.
  final String itemNo;

  final String description;
  final double quantity;
  final double unitPrice;
  final double amount;

  /// Parsed from `Amount_Including_VAT` when present and a number; `null`
  /// when the key is missing or explicitly `null`.
  ///
  /// The written API contract lists this as present on every row, but
  /// Lebanon/Iraq's real live `PostedSalesInvoiceDetails` page (confirmed
  /// 2026-09-02) publishes no VAT-inclusive figure at all — same confirmed
  /// contract-vs-deployment mismatch as [postingDate]. A *present but
  /// malformed or non-numeric* value still throws [FormatException] — only
  /// a missing key or an explicit JSON `null` is tolerated as "unknown".
  /// Never defaulted to `amount` or `0` — an unpublished VAT-inclusive
  /// figure must never be presented as a confirmed one.
  final double? amountIncludingVat;

  final String orderNo;

  /// The invoice's currency, e.g. `"OMR"`, `"USD"`, `"AED"` — confirmed
  /// live 2026-09-03 present on every tenant checked (Lebanon, Iraq, Oman),
  /// though sometimes blank (Lebanon). Same "blankable" contract as
  /// [LedgerEntry.currencyCode]: a missing key, explicit `null`, or `""` is
  /// a confirmed valid "unknown currency" value, not a malformed one —
  /// never `null` itself, and never defaulted to a guessed code like
  /// `"USD"` or `"$"` (see `formatCurrencyOrUnknown`, which every screen
  /// showing this field's amounts must go through instead of guessing).
  final String currencyCode;

  /// Parsed from `Invoice_Status` when present and non-blank (e.g.
  /// `"Paid"`, `"Open"`); `null` otherwise. Confirmed live 2026-09-03 on
  /// Oman's real invoices page; not part of the originally documented
  /// contract, so never required. Every value observed so far is a plain
  /// English word — this class does not enumerate or validate specific
  /// values, only parses the raw string; a caller rendering a status pill
  /// must handle an unrecognized value with a neutral style, never crash.
  final String? invoiceStatus;

  /// Parsed from `Due_Date` as a strict date-only value when present;
  /// `null` when missing, blank, `null`, or BC's `0001-01-01` "no date"
  /// sentinel (unlike [postingDate], which the confirmed contract lists as
  /// always present and never sentinel-valued — this field carries no such
  /// guarantee).
  final DateTime? dueDate;

  /// Parsed from `Payment_Method` when present and non-blank; `null`
  /// otherwise.
  final String? paymentMethod;

  /// Parsed from `Estimated_Delivery_Date` as a strict date-only value when
  /// present; `null` when missing, blank, `null`, or BC's sentinel — same
  /// tolerance as [dueDate].
  final DateTime? estimatedDeliveryDate;

  static final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _dateOnlyPrefixPattern = RegExp(r'^\d{4}-\d{2}-\d{2}');
  static const String _sentinelDate = '0001-01-01';

  factory BusinessCentralInvoiceLine.fromJson(Map<String, dynamic> json) {
    return BusinessCentralInvoiceLine(
      documentNo: _requireString(json, 'Document_No'),
      lineNo: _requireInt(json, 'Line_No'),
      postingDate: _optionalDateOnly(json, 'Posting_Date'),
      sellToCustomerNo: _requireString(json, 'Sell_to_Customer_No'),
      sellToCustomerName: _requireString(json, 'Sell_to_Customer_Name'),
      type: _requireString(json, 'Type'),
      itemNo: _requireString(json, 'No'),
      description: _requireString(json, 'Description'),
      quantity: _requireNum(json, 'Quantity'),
      unitPrice: _requireNum(json, 'Unit_Price'),
      amount: _requireNum(json, 'Amount'),
      amountIncludingVat: _optionalNum(json, 'Amount_Including_VAT'),
      orderNo: _requireString(json, 'Order_No'),
      currencyCode: _blankableCurrencyCode(json, 'Currency_Code'),
      invoiceStatus: _optionalNonEmptyString(json, 'Invoice_Status'),
      dueDate: _optionalDateOnlyOrSentinel(json, 'Due_Date'),
      paymentMethod: _optionalNonEmptyString(json, 'Payment_Method'),
      estimatedDeliveryDate: _optionalDateOnlyOrSentinel(
        json,
        'Estimated_Delivery_Date',
      ),
    );
  }

  static int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException(
        'BusinessCentralInvoiceLine.$key missing or not an int',
      );
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'BusinessCentralInvoiceLine.$key missing or not a number',
    );
  }

  /// Returns `null` when [key] is absent or explicitly JSON `null` — see
  /// [amountIncludingVat]'s doc comment. A *present* value must still be a
  /// number; any other present value (wrong type) throws [FormatException]
  /// rather than being silently treated as "also unknown".
  static double? _optionalNum(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'BusinessCentralInvoiceLine.$key was present but not a number',
    );
  }

  /// Requires [key] to be present and a [String] — nothing more. An empty
  /// string is a valid, documented value for every String field in this
  /// contract and is passed through unmodified: never trimmed, never
  /// replaced, never rejected.
  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException(
        'BusinessCentralInvoiceLine.$key missing or not a string',
      );
    }
    return value;
  }

  /// Returns `null` when [key] is absent or explicitly JSON `null` — the
  /// confirmed deployed-response shape for `Posting_Date` (see
  /// [postingDate]'s doc comment). A *present* value must still be a valid
  /// `yyyy-MM-dd` string; any other present value (wrong type, malformed
  /// date string) throws [FormatException] rather than being silently
  /// treated as "also unknown".
  static DateTime? _optionalDateOnly(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;

    final value = json[key];
    if (value is! String || !_dateOnlyPattern.hasMatch(value)) {
      throw FormatException(
        'BusinessCentralInvoiceLine.$key was present but not a '
        'yyyy-MM-dd date string',
      );
    }
    try {
      return DateTime.parse(value);
    } on FormatException {
      throw FormatException(
        'BusinessCentralInvoiceLine.$key was not a valid calendar date',
      );
    }
  }

  /// Returns `""` when [key] is absent or explicitly JSON `null` — the
  /// confirmed "unknown currency" contract shape (see [currencyCode]'s doc
  /// comment). A *present* value must still be a [String] (never trimmed);
  /// any other present value (wrong type) throws [FormatException] rather
  /// than being silently treated as "also blank".
  static String _blankableCurrencyCode(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return '';
    final value = json[key];
    if (value is! String) {
      throw FormatException(
        'BusinessCentralInvoiceLine.$key present but not a string',
      );
    }
    return value;
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
        'BusinessCentralInvoiceLine.$key present but not a string',
      );
    }
    return value.isEmpty ? null : value;
  }

  /// Returns `null` for an absent key, JSON `null`, a non-String value, an
  /// empty string, or BC's `0001-01-01` sentinel — used for the newer
  /// optional date fields ([dueDate]/[estimatedDeliveryDate]), which carry
  /// no guarantee of always being a genuine date the way [postingDate]'s
  /// confirmed contract does. A present value that starts with a valid
  /// `yyyy-MM-dd` prefix but still fails to parse throws, same as every
  /// other strict date field in this app.
  static DateTime? _optionalDateOnlyOrSentinel(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! String || value.isEmpty) return null;
    if (value.startsWith(_sentinelDate)) return null;
    if (!_dateOnlyPrefixPattern.hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value.substring(0, 10));
    if (parsed == null) {
      throw FormatException(
        'BusinessCentralInvoiceLine.$key was not a valid calendar date',
      );
    }
    return parsed;
  }

  /// Deliberately omits every other field — see the class-level doc
  /// comment.
  @override
  String toString() =>
      'BusinessCentralInvoiceLine(documentNo: $documentNo, lineNo: $lineNo)';
}
