import '../models/catalogue_lookup_result.dart';

// TODO: Replace this placeholder with catalogue/inventory lookup API once
// endpoint is confirmed.
final Map<String, CatalogueLookupResult> kMockCatalogueLookupResults = {
  'FAB-1001': const CatalogueLookupResult(
    status: CatalogueLookupStatus.success,
    catalogueCode: 'FAB-1001',
    availableQuantity: 320,
    warehouseName: 'Warehouse A',
  ),
  'FAB-2002': const CatalogueLookupResult(
    status: CatalogueLookupStatus.success,
    catalogueCode: 'FAB-2002',
    availableQuantity: 85,
    warehouseName: 'Warehouse B',
  ),
};
