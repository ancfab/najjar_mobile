// Fake InvoiceLookupDataSource for OrderDetailScreen tests: returns canned
// invoice lines (or throws, or stays pending) without exercising real HTTP
// or secure storage.

import 'package:anc_fabrics/models/business_central/business_central_invoice_line.dart';
import 'package:anc_fabrics/services/invoice_lookup_data_source.dart';

/// Builds a synthetic [BusinessCentralInvoiceLine] row for widget-test
/// fixtures.
BusinessCentralInvoiceLine sampleInvoiceLine({
  String documentNo = 'INV-24001',
  int lineNo = 10000,
  DateTime? postingDate,
  String sellToCustomerNo = 'CLNT-0001',
  String sellToCustomerName = 'Test Customer One',
  String type = 'Item',
  String itemNo = '880107',
  String description = 'Test Fabric Item',
  double quantity = 12,
  double unitPrice = 15,
  double amount = 180,
  double amountIncludingVat = 189,
  String orderNo = 'SO-24001',
}) {
  return BusinessCentralInvoiceLine(
    documentNo: documentNo,
    lineNo: lineNo,
    postingDate: postingDate,
    sellToCustomerNo: sellToCustomerNo,
    sellToCustomerName: sellToCustomerName,
    type: type,
    itemNo: itemNo,
    description: description,
    quantity: quantity,
    unitPrice: unitPrice,
    amount: amount,
    amountIncludingVat: amountIncludingVat,
    orderNo: orderNo,
  );
}

class FakeInvoiceLookupDataSource implements InvoiceLookupDataSource {
  FakeInvoiceLookupDataSource({this.lines, this.error, this.pendingFuture});

  /// Returned from [fetchInvoiceLinesForOrder] when set (and neither
  /// [error] nor [pendingFuture] is). Defaults to an empty list (no related
  /// invoice) when nothing is configured.
  final List<BusinessCentralInvoiceLine>? lines;

  /// When set, thrown from [fetchInvoiceLinesForOrder] instead of returning
  /// lines.
  final Object? error;

  /// When set, awaited instead of resolving immediately.
  final Future<List<BusinessCentralInvoiceLine>>? pendingFuture;

  int callCount = 0;
  final List<String> requestedOrderNos = [];

  @override
  Future<List<BusinessCentralInvoiceLine>> fetchInvoiceLinesForOrder({
    required String orderNo,
  }) async {
    callCount++;
    requestedOrderNos.add(orderNo);
    if (pendingFuture != null) return pendingFuture!;
    if (error != null) throw error!;
    return lines ?? const [];
  }
}
