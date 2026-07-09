import '../data/mock_catalogue_lookup_data.dart';
import '../models/catalogue_lookup_result.dart';

/// Looks up fabric availability details for a given catalogue code.
class CatalogueLookupService {
  const CatalogueLookupService();

  /// Searches fabric availability by catalogue code.
  ///
  /// TODO: Replace this placeholder with catalogue/inventory lookup API
  /// once endpoint is confirmed.
  Future<CatalogueLookupResult> searchFabricAvailabilityByCatalogueCode(
    String catalogueCode,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final normalizedCode = catalogueCode.trim().toUpperCase();
    return kMockCatalogueLookupResults[normalizedCode] ??
        CatalogueLookupResult(
          status: CatalogueLookupStatus.notFound,
          catalogueCode: normalizedCode,
        );
  }
}
