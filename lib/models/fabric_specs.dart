/// Mock fabric specification fields shown in the Fabric Specs bottom sheet,
/// opened from the Order Detail screen's Order Items card.
///
/// once the backend/API response shape is confirmed.
class FabricSpecs {
  const FabricSpecs({
    required this.fabricName,
    required this.sku,
    required this.color,
    required this.weight,
    required this.quantity,
    this.composition,
  });

  final String fabricName;
  final String sku;
  final String color;

  /// Weight/GSM, pre-formatted for display (e.g. "320 GSM").
  final String weight;

  final String quantity;

  /// Fabric composition (e.g. "100% Cotton"). Optional since composition is
  /// not confirmed to exist for every fabric type yet.
  final String? composition;
}
