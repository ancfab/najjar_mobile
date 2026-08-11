/// Purpose: One row of the Business Central items endpoint's *grouped*
/// response — returned only when the request includes a `search` query
/// parameter (see `AncApiClient.searchItems`). Distinct from
/// [BusinessCentralItem], which models a flat `/items` row (no `search`
/// parameter); this file must never weaken or reuse that model, since the
/// confirmed live contract for the two response shapes is different.
///
/// Confirmed live example (`GET /items?search=1012`): a `commonItemNo` of
/// `1012` grouped 12 variations (`1012A01`..`1012C04`) under one
/// `totalInventory`. The exact JSON shape of one `variations` entry was not
/// captured in that verification pass — only the count was confirmed — so
/// [BusinessCentralItemVariation] only requires the two fields that carry
/// row identity ([BusinessCentralItemVariation.id]/
/// [BusinessCentralItemVariation.itemNo]) and treats every other documented
/// field as optional rather than guessing a stricter contract than what was
/// actually observed.
///
/// Must not:
/// - Be constructed from, or fed into, [BusinessCentralItem] parsing.
/// - Be treated as a source of final stock availability — that remains
///   `GET /inventory?item_no=...` via `StockLookupService`, exactly as
///   before (see `ApiStockLookupService`).
library;

/// One catalogue group from a grouped `/items?search=...` response: a
/// `commonItemNo` and the variations Business Central rolled up under it.
class BusinessCentralItemSearchGroup {
  const BusinessCentralItemSearchGroup({
    required this.commonItemNo,
    required this.totalInventory,
    required this.variations,
  });

  /// Always non-empty — the identity this feature's exact-match resolver
  /// compares the user's entered search text against (case-insensitively,
  /// trimmed). See `resolveExactCommonItemGroup`.
  final String commonItemNo;

  /// Group-level total inventory across every variation, exactly as
  /// returned — never a substitute for a selected variation's own
  /// location-scoped availability (`GET /inventory?item_no=...`). May
  /// legitimately be zero; a negative value, if the backend ever sends one,
  /// is carried through as-is rather than rejected, since this class has no
  /// confirmed evidence that Business Central restricts it to `>= 0`.
  final double totalInventory;

  /// The variations Business Central rolled up under [commonItemNo]. May be
  /// empty; never deduplicated or reordered here.
  final List<BusinessCentralItemVariation> variations;

  factory BusinessCentralItemSearchGroup.fromJson(Map<String, dynamic> json) {
    final rawVariations = json['variations'];
    if (rawVariations is! List) {
      throw const FormatException(
        'BusinessCentralItemSearchGroup.variations missing or not a JSON array',
      );
    }

    return BusinessCentralItemSearchGroup(
      commonItemNo: _requireNonEmptyString(json, 'commonItemNo'),
      totalInventory: _requireNum(json, 'totalInventory'),
      variations: [
        for (final row in rawVariations)
          if (row is Map<String, dynamic>)
            BusinessCentralItemVariation.fromJson(row)
          else
            throw const FormatException(
              'BusinessCentralItemSearchGroup.variations contains a '
              'non-object row',
            ),
      ],
    );
  }

  static String _requireNonEmptyString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'BusinessCentralItemSearchGroup.$key missing, not a string, or empty',
      );
    }
    return value;
  }

  static double _requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException(
      'BusinessCentralItemSearchGroup.$key missing or not a number',
    );
  }

  @override
  String toString() =>
      'BusinessCentralItemSearchGroup(commonItemNo: $commonItemNo, '
      'variations: ${variations.length})';
}

/// One variation inside a [BusinessCentralItemSearchGroup.variations] list.
///
/// Only [id]/[itemNo] are required — see this file's library doc comment
/// for why every other field is optional here rather than mirroring
/// [BusinessCentralItem]'s stricter required-string contract.
class BusinessCentralItemVariation {
  const BusinessCentralItemVariation({
    required this.id,
    required this.itemNo,
    this.commonItemNo,
    this.description,
    this.baseUnitOfMeasure,
    this.inventory,
  });

  /// Stable row identity, mirroring [BusinessCentralItem.id]. Always
  /// non-empty.
  final String id;

  /// The exact Business Central item number this variation resolves to once
  /// selected — passed to `StockLookupService.lookup` unchanged. Always
  /// non-empty.
  final String itemNo;

  final String? commonItemNo;
  final String? description;
  final String? baseUnitOfMeasure;
  final double? inventory;

  factory BusinessCentralItemVariation.fromJson(Map<String, dynamic> json) {
    return BusinessCentralItemVariation(
      id: _requireNonEmptyString(json, 'id'),
      itemNo: _requireNonEmptyString(json, 'itemNo'),
      commonItemNo: _optionalString(json, 'commonItemNo'),
      description: _optionalString(json, 'description'),
      baseUnitOfMeasure: _optionalString(json, 'baseUnitOfMeasure'),
      inventory: _optionalNum(json, 'inventory'),
    );
  }

  static String _requireNonEmptyString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'BusinessCentralItemVariation.$key missing, not a string, or empty',
      );
    }
    return value;
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException(
        'BusinessCentralItemVariation.$key was not a string',
      );
    }
    return value;
  }

  static double? _optionalNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException('BusinessCentralItemVariation.$key was not a number');
  }

  @override
  String toString() => 'BusinessCentralItemVariation(id: $id, itemNo: $itemNo)';
}
