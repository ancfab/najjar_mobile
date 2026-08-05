// Fake OrderDetailDataSource for OrderDetailScreen tests: returns canned
// sales-order lines (or throws, or stays pending) without exercising real
// HTTP or secure storage.

import 'package:anc_fabrics/models/business_central/sales_order_line.dart';
import 'package:anc_fabrics/services/order_detail_data_source.dart';

class FakeOrderDetailDataSource implements OrderDetailDataSource {
  FakeOrderDetailDataSource({this.lines, this.error, this.pendingFuture});

  /// Returned from [fetchOrder] when set (and neither [error] nor
  /// [pendingFuture] is). Defaults to a single sample line for
  /// [documentNo] when nothing is configured.
  final List<BusinessCentralSalesOrderLine>? lines;

  /// When set, thrown from [fetchOrder] instead of returning lines.
  final Object? error;

  /// When set, awaited instead of resolving immediately — lets a test
  /// observe the loading state before controlling exactly when/how the
  /// call completes.
  final Future<List<BusinessCentralSalesOrderLine>>? pendingFuture;

  int callCount = 0;
  final List<String> requestedDocumentNos = [];

  @override
  Future<List<BusinessCentralSalesOrderLine>> fetchOrder({
    required String documentNo,
  }) async {
    callCount++;
    requestedDocumentNos.add(documentNo);
    if (pendingFuture != null) return pendingFuture!;
    if (error != null) throw error!;
    return lines ?? [_sampleLine(documentNo)];
  }

  BusinessCentralSalesOrderLine _sampleLine(String documentNo) =>
      BusinessCentralSalesOrderLine(
        documentNo: documentNo,
        lineNo: 10000,
        sellToCustomerNo: 'CLNT-0001',
        sellToCustomerName: 'Test Customer One',
        itemNo: '880107',
        description: 'Test Fabric Item',
        quantity: 12,
        unitPrice: 15,
        amount: 180,
      );
}
