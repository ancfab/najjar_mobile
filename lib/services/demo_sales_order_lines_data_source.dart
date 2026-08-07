import '../config/api_config.dart';
import '../models/business_central/paginated_response.dart';
import '../models/business_central/sales_order_line.dart';
import 'sales_order_lines_data_source.dart';

/// TEMPORARY CLIENT DEMO MODE [SalesOrderLinesDataSource]: returns a fixed,
/// realistic single page of [BusinessCentralSalesOrderLine] rows with no
/// I/O — never calls the live sales-orders endpoint. Selected in place of
/// [LiveSalesOrderLinesDataSource] only when [DemoConfig.useDemoOrders]
/// (`demo_config.dart`) is `true`; see `OrdersScreen`'s
/// `resolveDefaultSalesOrderLinesDataSource`.
///
/// Always resolves to the same fixed page regardless of the requested
/// [fetchPage] `page`/`perPage` — this demo dataset is intentionally a
/// single page (`current_page`/`last_page` both `1`, `next_page_url` and
/// `prev_page_url` both `null`), so the Previous/Next controls render but
/// stay disabled, matching how a real single-page result would look.
class DemoSalesOrderLinesDataSource implements SalesOrderLinesDataSource {
  const DemoSalesOrderLinesDataSource();

  /// Mock sales-order lines shown during client demos — four distinct
  /// `Document_No` values, some with multiple lines, so the "one row per
  /// line, grouped by document on Order Detail" behavior still looks
  /// realistic.
  static const List<BusinessCentralSalesOrderLine> mockLines = [
    BusinessCentralSalesOrderLine(
      documentNo: 'SO-100234',
      lineNo: 10000,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      itemNo: 'FAB-COT-320',
      description: 'Premium Cotton Twill - Ivory White',
      quantity: 280,
      unitPrice: 17.14,
      amount: 4800.00,
    ),
    BusinessCentralSalesOrderLine(
      documentNo: 'SO-100234',
      lineNo: 20000,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      itemNo: 'FAB-COT-321',
      description: 'Premium Cotton Twill - Slate Blue',
      quantity: 120,
      unitPrice: 17.14,
      amount: 2056.80,
    ),
    BusinessCentralSalesOrderLine(
      documentNo: 'SO-100235',
      lineNo: 10000,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      itemNo: 'FAB-WOL-410',
      description: 'Italian Wool Blend - Charcoal Grey',
      quantity: 150,
      unitPrice: 41.33,
      amount: 6200.00,
    ),
    BusinessCentralSalesOrderLine(
      documentNo: 'SO-100236',
      lineNo: 10000,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      itemNo: 'FAB-LIN-505',
      description: 'Egyptian Linen - Natural Beige',
      quantity: 320,
      unitPrice: 12.34,
      amount: 3950.00,
    ),
    BusinessCentralSalesOrderLine(
      documentNo: 'SO-100236',
      lineNo: 20000,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      itemNo: 'FAB-LIN-506',
      description: 'Egyptian Linen - Ivory White',
      quantity: 95,
      unitPrice: 13.42,
      amount: 1275.00,
    ),
    BusinessCentralSalesOrderLine(
      documentNo: 'SO-100237',
      lineNo: 10000,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      itemNo: 'FAB-SLK-610',
      description: 'Bamboo Silk Charmeuse - Champagne Gold',
      quantity: 60,
      unitPrice: 44.00,
      amount: 2640.00,
    ),
  ];

  /// The fixed single-page [PaginatedResponse] wrapping [mockLines].
  static final PaginatedResponse<BusinessCentralSalesOrderLine> mockPage =
      PaginatedResponse<BusinessCentralSalesOrderLine>(
        currentPage: 1,
        data: mockLines,
        firstPageUrl:
            '${ApiConfig.baseUrl}/${ApiConfig.salesOrdersPath}?page=1',
        from: 1,
        lastPage: 1,
        lastPageUrl: '${ApiConfig.baseUrl}/${ApiConfig.salesOrdersPath}?page=1',
        nextPageUrl: null,
        path: '${ApiConfig.baseUrl}/${ApiConfig.salesOrdersPath}',
        perPage: mockLines.length,
        prevPageUrl: null,
        to: mockLines.length,
        total: mockLines.length,
      );

  @override
  Future<PaginatedResponse<BusinessCentralSalesOrderLine>> fetchPage({
    required int page,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async => mockPage;
}
