import '../models/business_central/zebra_sales_order_line.dart';
import 'zebra_order_detail_service.dart';

/// Purpose: The seam `OrderDetailScreen` depends on for its best-effort
/// Zebra-detail enrichment fetch — abstract so widget tests can inject a
/// fake instead of exercising real HTTP/secure storage, matching the
/// existing `OrderDetailDataSource` injectable-service convention.
abstract class ZebraOrderDetailDataSource {
  /// Returns every Zebra sales-order line for [documentNo] (already
  /// deduplicated and page-accumulated), or an empty list when there is no
  /// Zebra detail for this order - see `ZebraOrderDetailService.fetchOrder`'s
  /// doc comment for the full list of cases that means. Throws
  /// `SessionExpiredException` on a dead session - never any other
  /// exception, and never mock data.
  Future<List<BusinessCentralZebraSalesOrderLine>> fetchOrder({
    required String documentNo,
  });
}

/// Default [ZebraOrderDetailDataSource]: loads via [ZebraOrderDetailService],
/// the confirmed `GET /api/business-central/zebra-sales-orders?document_no=...`
/// contract.
class LiveZebraOrderDetailDataSource implements ZebraOrderDetailDataSource {
  LiveZebraOrderDetailDataSource({ZebraOrderDetailService? service})
    : _service = service ?? ZebraOrderDetailService();

  final ZebraOrderDetailService _service;

  @override
  Future<List<BusinessCentralZebraSalesOrderLine>> fetchOrder({
    required String documentNo,
  }) => _service.fetchOrder(documentNo: documentNo);
}
