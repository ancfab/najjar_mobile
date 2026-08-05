import '../models/business_central/sales_order_line.dart';
import 'order_detail_service.dart';

/// Purpose: The seam `OrderDetailScreen` depends on for its live order-line
/// fetch — abstract so widget tests can inject a fake instead of exercising
/// real HTTP/secure storage, matching the existing
/// `SalesOrderLinesDataSource` injectable-service convention.
abstract class OrderDetailDataSource {
  /// Returns every sales-order line for [documentNo] (already deduplicated
  /// and page-accumulated), or an empty list when no such order exists.
  /// Throws `SessionExpiredException` or `BusinessCentralFailureException`
  /// on failure — never a raw `AncApiException` or platform exception, and
  /// never mock data.
  Future<List<BusinessCentralSalesOrderLine>> fetchOrder({
    required String documentNo,
  });
}

/// Default [OrderDetailDataSource]: loads via [OrderDetailService], the
/// confirmed `GET /api/business-central/sales-orders?document_no=...`
/// contract.
class LiveOrderDetailDataSource implements OrderDetailDataSource {
  LiveOrderDetailDataSource({OrderDetailService? orderDetailService})
    : _orderDetailService = orderDetailService ?? OrderDetailService();

  final OrderDetailService _orderDetailService;

  @override
  Future<List<BusinessCentralSalesOrderLine>> fetchOrder({
    required String documentNo,
  }) => _orderDetailService.fetchOrder(documentNo: documentNo);
}
