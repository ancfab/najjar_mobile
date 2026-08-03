/// Purpose: One row of the Business Central items (product catalog)
/// endpoint's paginated response.
///
/// Responsibilities:
/// - Parse the exact camelCase backend keys this endpoint's confirmed live
///   contract defines (`id`, `itemNo`, `commonItemNo`, `description`,
///   `description2`, `baseUnitOfMeasure`, `itemCategoryCode`,
///   `productGroupCode`, `blocked`, `inventory`, `unitPrice`, `gtin`) —
///   never a PascalCase_With_Underscores variant; Business Central naming
///   is inconsistent between endpoints (compare `LedgerEntry`/
///   `BusinessCentralInvoiceLine` against `PaymentEntry`), so this parser
///   must not accept those as aliases.
/// - Parse `inventory`/`unitPrice` as `double` whether the backend sends an
///   integer or a decimal.
/// - Require every documented String field to be present and typed as a
///   `String`, without inventing a non-empty rule the contract doesn't
///   state — the confirmed live response allows `description2`,
///   `itemCategoryCode`, `productGroupCode`, and `gtin` to be empty
///   strings (same reasoning as `PaymentEntry._requireString`).
/// - Require [id] and [itemNo] specifically to be non-empty: [id] is the
///   sole identity `ItemsService` deduplicates paginated rows by, so an
///   accepted empty [id] would let two distinct rows silently collapse
///   into one under the same `""` key; [itemNo] is the primary Business
///   Central display/business identifier and must always identify a real
///   item. No other field carries that identity/business role, so no
///   other field gets this stricter check.
/// - Ignore every undocumented/internal key the live response also returns
///   (`@odata.etag`, `Global_Dimension_1_Filter`, `Global_Dimension_2_Filter`,
///   `Location_Filter`, `Drop_Shipment_Filter`, `Variant_Filter`,
///   `Lot_No_Filter`, `Serial_No_Filter`, `Unit_of_Measure_Filter`,
///   `Package_No_Filter`) — this class only ever reads its own approved
///   keys, so extra keys never cause a parse failure and are never
///   retained.
/// - Throw a [FormatException] — never an uncontrolled cast error, and
///   never a silently-applied fallback value — for any missing or
///   malformed required field.
///
/// Must not:
/// - Model, store, expose, or log any internal cost/margin field, or any
///   OData metadata field (`@odata.etag`) — those are not part of the
///   approved mobile contract.
/// - Assign a business meaning to [blocked] (e.g. filtering it out of a
///   list) — that is a UI/business decision left to a later phase; this
///   class only carries the flag.
class BusinessCentralItem {
  const BusinessCentralItem({
    required this.id,
    required this.itemNo,
    required this.commonItemNo,
    required this.description,
    required this.description2,
    required this.baseUnitOfMeasure,
    required this.itemCategoryCode,
    required this.productGroupCode,
    required this.blocked,
    required this.inventory,
    required this.unitPrice,
    required this.gtin,
  });

  /// Stable row identity for this item (a UUID-like string in the
  /// confirmed live response) — the correct identity to deduplicate
  /// paginated rows by. Never use [commonItemNo] for that: multiple item
  /// variants share the same [commonItemNo]. Always non-empty (see the
  /// class-level doc comment for why an empty value is rejected).
  final String id;

  /// The primary Business Central display/business identifier for this
  /// item. Always non-empty.
  final String itemNo;
  final String commonItemNo;
  final String description;
  final String description2;
  final String baseUnitOfMeasure;
  final String itemCategoryCode;
  final String productGroupCode;

  /// Whether Business Central has blocked this item. Carried through
  /// as-is; deciding whether/how to hide a blocked item from the user is
  /// explicitly out of scope for this model.
  final bool blocked;

  final double inventory;
  final double unitPrice;
  final String gtin;

  factory BusinessCentralItem.fromJson(Map<String, dynamic> json) {
    return BusinessCentralItem(
      id: _requireNonEmptyString(json, 'id'),
      itemNo: _requireNonEmptyString(json, 'itemNo'),
      commonItemNo: _requireString(json, 'commonItemNo'),
      description: _requireString(json, 'description'),
      description2: _requireString(json, 'description2'),
      baseUnitOfMeasure: _requireString(json, 'baseUnitOfMeasure'),
      itemCategoryCode: _requireString(json, 'itemCategoryCode'),
      productGroupCode: _requireString(json, 'productGroupCode'),
      blocked: _requireBool(json, 'blocked'),
      inventory: _requireNum(json, 'inventory'),
      unitPrice: _requireNum(json, 'unitPrice'),
      gtin: _requireString(json, 'gtin'),
    );
  }

  /// Requires [key] to be present and a [String] — nothing more. Several
  /// fields on this contract are confirmed to be empty strings on live
  /// rows, so no field here enforces a non-empty rule the contract doesn't
  /// state.
  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('BusinessCentralItem.$key missing or not a string');
    }
    return value;
  }

  /// Requires [key] to be present, a [String], and non-empty — stricter
  /// than [_requireString]. Reserved for [id]/[itemNo] only: see the
  /// class-level doc comment for why those two specifically must never be
  /// empty.
  static String _requireNonEmptyString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'BusinessCentralItem.$key missing, not a string, or empty',
      );
    }
    return value;
  }

  static bool _requireBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException('BusinessCentralItem.$key missing or not a bool');
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException('BusinessCentralItem.$key missing or not a number');
  }

  /// Deliberately omits [unitPrice]/[inventory] — see the class-level doc
  /// comment.
  @override
  String toString() => 'BusinessCentralItem(id: $id, itemNo: $itemNo)';
}
