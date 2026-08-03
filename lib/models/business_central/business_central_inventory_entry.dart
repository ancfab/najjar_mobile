/// Purpose: One row of the Business Central inventory endpoint's paginated
/// response.
///
/// Responsibilities:
/// - Parse the exact documented camelCase keys (`id`, `entryNo`,
///   `postingDate`, `documentType`, `documentNo`, `itemNo`, `description`,
///   `locationCode`, `quantity`, `remainingQuantity`, `unitOfMeasureCode`,
///   `open`) — never a PascalCase_With_Underscores variant; Business Central
///   naming is inconsistent between endpoints (compare `LedgerEntry` against
///   `BusinessCentralItem`/`PaymentEntry`), so this parser must not accept
///   those as aliases.
/// - Parse `quantity`/`remainingQuantity` as `double` whether the backend
///   sends an integer or a decimal.
/// - Keep [postingDate] as a raw `String` rather than a parsed `DateTime` —
///   unlike `LedgerEntry`/`PaymentEntry`, this endpoint's date format has not
///   been confirmed against a live response, so this class does not invent a
///   `yyyy-MM-dd` parsing rule the documented contract does not state.
/// - Require [id] and [itemNo] specifically to be non-empty: [id] is the
///   identity `InventoryService` deduplicates paginated rows by, and
///   [itemNo] is the Business Central item identifier this endpoint exists
///   to report on. No other field carries that identity/business role, so no
///   other field gets this stricter check.
/// - Ignore every undocumented/internal key a live response might also
///   return — this class only ever reads its own approved keys, so extra
///   keys never cause a parse failure and are never retained.
/// - Throw a [FormatException] — never an uncontrolled cast error, and
///   never a silently-applied fallback value — for any missing or malformed
///   required field.
///
/// Must not:
/// - Model, store, expose, or log any vendor-reference, OData metadata, or
///   cost/margin field — those are not part of the approved mobile contract
///   and are intentionally stripped by the backend.
/// - Assign a business meaning to [open] (e.g. filtering it out of a list)
///   — that is a UI/business decision left to a later phase; this class
///   only carries the flag.
class BusinessCentralInventoryEntry {
  const BusinessCentralInventoryEntry({
    required this.id,
    required this.entryNo,
    required this.postingDate,
    required this.documentType,
    required this.documentNo,
    required this.itemNo,
    required this.description,
    required this.locationCode,
    required this.quantity,
    required this.remainingQuantity,
    required this.unitOfMeasureCode,
    required this.open,
  });

  /// Stable row identity for this entry — the identity `InventoryService`
  /// deduplicates paginated rows by. Always non-empty (see the class-level
  /// doc comment for why an empty value is rejected).
  final String id;

  final int entryNo;

  /// Raw, unparsed date string as documented by the endpoint's contract —
  /// see the class-level doc comment for why this is not a `DateTime`.
  final String postingDate;

  final String documentType;
  final String documentNo;

  /// The Business Central item identifier this entry reports quantity
  /// against. Always non-empty.
  final String itemNo;

  final String description;
  final String locationCode;
  final double quantity;
  final double remainingQuantity;
  final String unitOfMeasureCode;

  /// Whether this entry is still open. Carried through as-is; deciding
  /// whether/how to filter on this flag is explicitly out of scope for this
  /// model.
  final bool open;

  factory BusinessCentralInventoryEntry.fromJson(Map<String, dynamic> json) {
    return BusinessCentralInventoryEntry(
      id: _requireNonEmptyString(json, 'id'),
      entryNo: _requireInt(json, 'entryNo'),
      postingDate: _requireString(json, 'postingDate'),
      documentType: _requireString(json, 'documentType'),
      documentNo: _requireString(json, 'documentNo'),
      itemNo: _requireNonEmptyString(json, 'itemNo'),
      description: _requireString(json, 'description'),
      locationCode: _requireString(json, 'locationCode'),
      quantity: _requireNum(json, 'quantity'),
      remainingQuantity: _requireNum(json, 'remainingQuantity'),
      unitOfMeasureCode: _requireString(json, 'unitOfMeasureCode'),
      open: _requireBool(json, 'open'),
    );
  }

  /// Requires [key] to be present and a [String] — nothing more. No field
  /// here enforces a non-empty rule the documented contract doesn't state,
  /// other than [id]/[itemNo] (see [_requireNonEmptyString]).
  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException(
        'BusinessCentralInventoryEntry.$key missing or not a string',
      );
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
        'BusinessCentralInventoryEntry.$key missing, not a string, or empty',
      );
    }
    return value;
  }

  static int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException(
        'BusinessCentralInventoryEntry.$key missing or not an int',
      );
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'BusinessCentralInventoryEntry.$key missing or not a number',
    );
  }

  static bool _requireBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw FormatException(
        'BusinessCentralInventoryEntry.$key missing or not a bool',
      );
    }
    return value;
  }

  /// Deliberately omits [quantity]/[remainingQuantity] — see the
  /// class-level doc comment convention shared with `BusinessCentralItem`.
  @override
  String toString() =>
      'BusinessCentralInventoryEntry(id: $id, itemNo: $itemNo, '
      'entryNo: $entryNo)';
}
