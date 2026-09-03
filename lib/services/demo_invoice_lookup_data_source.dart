import '../models/business_central/business_central_invoice_line.dart';
import 'invoice_lookup_data_source.dart';

/// TEMPORARY CLIENT DEMO MODE [InvoiceLookupDataSource]: resolves every
/// invoice line whose `Order_No` equals the requested `orderNo` from a fixed,
/// realistic dataset — never calls the live invoices endpoint. Selected in
/// place of [LiveInvoiceLookupDataSource] only when [DemoConfig.useDemoOrders]
/// (`demo_config.dart`) is `true`; see `resolveDefaultInvoiceLookupDataSource`
/// in `order_detail_screen.dart`.
///
/// Every invoiced [mockLines] row corresponds to a
/// [DemoSalesOrderLinesDataSource.mockLines] order line (same item,
/// quantity, unit price, and `Amount`, plus 5% VAT for
/// `Amount_Including_VAT`) so the demo invoice a user opens always matches
/// the demo order it was opened from. `SO-100237` is deliberately left
/// without an invoice — a recently placed order with no invoice yet — so the
/// demo also exercises the "no invoice available" path.
class DemoInvoiceLookupDataSource implements InvoiceLookupDataSource {
  const DemoInvoiceLookupDataSource();

  static const List<BusinessCentralInvoiceLine> mockLines = [
    // Invoice INV-100234 for order SO-100234.
    BusinessCentralInvoiceLine(
      documentNo: 'INV-100234',
      lineNo: 10000,
      postingDate: null,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      type: 'Item',
      itemNo: 'FAB-COT-320',
      description: 'Premium Cotton Twill - Ivory White',
      quantity: 280,
      unitPrice: 17.14,
      amount: 4800.00,
      amountIncludingVat: 5040.00,
      orderNo: 'SO-100234',
      currencyCode: 'USD',
    ),
    BusinessCentralInvoiceLine(
      documentNo: 'INV-100234',
      lineNo: 20000,
      postingDate: null,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      type: 'Item',
      itemNo: 'FAB-COT-321',
      description: 'Premium Cotton Twill - Slate Blue',
      quantity: 120,
      unitPrice: 17.14,
      amount: 2056.80,
      amountIncludingVat: 2159.64,
      orderNo: 'SO-100234',
      currencyCode: 'USD',
    ),

    // Invoice INV-100235 for order SO-100235.
    BusinessCentralInvoiceLine(
      documentNo: 'INV-100235',
      lineNo: 10000,
      postingDate: null,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      type: 'Item',
      itemNo: 'FAB-WOL-410',
      description: 'Italian Wool Blend - Charcoal Grey',
      quantity: 150,
      unitPrice: 41.33,
      amount: 6200.00,
      amountIncludingVat: 6510.00,
      orderNo: 'SO-100235',
      currencyCode: 'USD',
    ),

    // Invoice INV-100236 for order SO-100236.
    BusinessCentralInvoiceLine(
      documentNo: 'INV-100236',
      lineNo: 10000,
      postingDate: null,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      type: 'Item',
      itemNo: 'FAB-LIN-505',
      description: 'Egyptian Linen - Natural Beige',
      quantity: 320,
      unitPrice: 12.34,
      amount: 3950.00,
      amountIncludingVat: 4147.50,
      orderNo: 'SO-100236',
      currencyCode: 'USD',
    ),
    BusinessCentralInvoiceLine(
      documentNo: 'INV-100236',
      lineNo: 20000,
      postingDate: null,
      sellToCustomerNo: 'C-10045',
      sellToCustomerName: 'ANC Textiles Trading LLC',
      type: 'Item',
      itemNo: 'FAB-LIN-506',
      description: 'Egyptian Linen - Ivory White',
      quantity: 95,
      unitPrice: 13.42,
      amount: 1275.00,
      amountIncludingVat: 1338.75,
      orderNo: 'SO-100236',
      currencyCode: 'USD',
    ),

    // SO-100237 intentionally has no invoice yet.
  ];

  @override
  Future<List<BusinessCentralInvoiceLine>> fetchInvoiceLinesForOrder({
    required String orderNo,
  }) async {
    return mockLines
        .where((line) => line.orderNo == orderNo)
        .toList(growable: false);
  }
}
