import '../models/business_central/business_central_invoice_line.dart';
import 'invoice_lookup_service.dart';

/// Purpose: The seam `OrderDetailScreen` depends on for its live Invoice
/// button lookup — abstract so widget tests can inject a fake instead of
/// exercising real HTTP/secure storage, matching the existing
/// `OrderDetailDataSource`/`SalesOrderLinesDataSource` injectable-service
/// convention.
abstract class InvoiceLookupDataSource {
  /// Returns every invoice line related to [orderNo] (already deduplicated
  /// and page-accumulated), or an empty list when no invoice is related to
  /// this order. Throws `SessionExpiredException` or
  /// `BusinessCentralFailureException` on failure — never a raw
  /// `AncApiException` or platform exception, and never mock data.
  Future<List<BusinessCentralInvoiceLine>> fetchInvoiceLinesForOrder({
    required String orderNo,
  });
}

/// Default [InvoiceLookupDataSource]: loads via [InvoiceLookupService], the
/// confirmed `GET /api/business-central/invoices?order_no=...` contract.
class LiveInvoiceLookupDataSource implements InvoiceLookupDataSource {
  LiveInvoiceLookupDataSource({InvoiceLookupService? invoiceLookupService})
    : _invoiceLookupService = invoiceLookupService ?? InvoiceLookupService();

  final InvoiceLookupService _invoiceLookupService;

  @override
  Future<List<BusinessCentralInvoiceLine>> fetchInvoiceLinesForOrder({
    required String orderNo,
  }) => _invoiceLookupService.fetchInvoiceLinesForOrder(orderNo: orderNo);
}
