/// Outcome of a fabric availability lookup by catalogue code.
enum CatalogueLookupStatus { success, notFound }

/// Result returned when looking up fabric availability for a catalogue code.
class CatalogueLookupResult {
  const CatalogueLookupResult({
    required this.status,
    required this.catalogueCode,
    this.availableQuantity,
    this.warehouseName,
  });

  final CatalogueLookupStatus status;
  final String catalogueCode;

  /// Quantity available, in yards. Only set when [status] is `success`.
  final int? availableQuantity;

  /// Warehouse holding the stock. Only set when [status] is `success`.
  final String? warehouseName;
}
