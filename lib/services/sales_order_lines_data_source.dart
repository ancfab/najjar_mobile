import '../config/api_config.dart';
import '../models/business_central/paginated_response.dart';
import '../models/business_central/sales_order_line.dart';
import 'sales_order_lines_service.dart';

/// Purpose: The seam `OrdersScreen` depends on for its live sales-order-line
/// pages — abstract so widget tests can inject a fake instead of exercising
/// real HTTP/secure storage, matching the existing
/// `LastPaymentDataSource`/`CurrentBalanceDataSource` injectable-service
/// convention.
abstract class SalesOrderLinesDataSource {
  /// Returns one page of sales-order lines. Throws `SessionExpiredException`
  /// or `BusinessCentralFailureException` (see `business_central_error_
  /// mapper.dart`) on failure — never a raw `AncApiException` or platform
  /// exception, and never mock data.
  Future<PaginatedResponse<BusinessCentralSalesOrderLine>> fetchPage({
    required int page,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  });
}

/// Default [SalesOrderLinesDataSource]: loads one page via
/// [SalesOrderLinesService], the confirmed
/// `GET /api/business-central/sales-orders` endpoint.
class LiveSalesOrderLinesDataSource implements SalesOrderLinesDataSource {
  LiveSalesOrderLinesDataSource({
    SalesOrderLinesService? salesOrderLinesService,
  }) : _salesOrderLinesService =
           salesOrderLinesService ?? SalesOrderLinesService();

  final SalesOrderLinesService _salesOrderLinesService;

  @override
  Future<PaginatedResponse<BusinessCentralSalesOrderLine>> fetchPage({
    required int page,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) => _salesOrderLinesService.fetchPage(page: page, perPage: perPage);
}
