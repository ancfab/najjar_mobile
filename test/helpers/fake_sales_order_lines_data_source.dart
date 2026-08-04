// Fake SalesOrderLinesDataSource for OrdersScreen tests: returns a canned
// PaginatedResponse (or throws, or stays pending) without exercising real
// HTTP or secure storage.

import 'package:anc_fabrics/models/business_central/paginated_response.dart';
import 'package:anc_fabrics/models/business_central/sales_order_line.dart';
import 'package:anc_fabrics/services/sales_order_lines_data_source.dart';

/// Builds a synthetic [BusinessCentralSalesOrderLine] row, distinct from
/// any mock `FabricOrder` fixture, for widget-test fixtures.
BusinessCentralSalesOrderLine sampleSalesOrderLine({
  String documentNo = 'SO-24001',
  int lineNo = 10000,
  String sellToCustomerNo = 'CLNT-0001',
  String sellToCustomerName = 'Test Customer One',
  String itemNo = '880107',
  String description = 'Test Fabric Item',
  double quantity = 12,
  double unitPrice = 15,
  double amount = 180,
}) {
  return BusinessCentralSalesOrderLine(
    documentNo: documentNo,
    lineNo: lineNo,
    sellToCustomerNo: sellToCustomerNo,
    sellToCustomerName: sellToCustomerName,
    itemNo: itemNo,
    description: description,
    quantity: quantity,
    unitPrice: unitPrice,
    amount: amount,
  );
}

/// Builds a synthetic paginated envelope around [rows], defaulting to a
/// single full page (`current_page` 1 of 1) unless overridden.
PaginatedResponse<BusinessCentralSalesOrderLine> samplePage({
  List<BusinessCentralSalesOrderLine>? rows,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 25,
  int? total,
  String? nextPageUrl,
  String? prevPageUrl,
}) {
  final data = rows ?? [sampleSalesOrderLine()];
  // Mirrors a real Laravel paginator: next/prev URLs are non-null exactly
  // when a next/previous page actually exists, unless a test explicitly
  // overrides one to exercise a specific edge case.
  final resolvedNextPageUrl =
      nextPageUrl ??
      (currentPage < lastPage
          ? 'https://api.ancfab.com/api/business-central/sales-orders?page=${currentPage + 1}'
          : null);
  final resolvedPrevPageUrl =
      prevPageUrl ??
      (currentPage > 1
          ? 'https://api.ancfab.com/api/business-central/sales-orders?page=${currentPage - 1}'
          : null);
  return PaginatedResponse<BusinessCentralSalesOrderLine>(
    currentPage: currentPage,
    data: data,
    firstPageUrl:
        'https://api.ancfab.com/api/business-central/sales-orders?page=1',
    from: data.isEmpty ? null : ((currentPage - 1) * perPage) + 1,
    lastPage: lastPage,
    lastPageUrl:
        'https://api.ancfab.com/api/business-central/sales-orders?page=$lastPage',
    nextPageUrl: resolvedNextPageUrl,
    path: 'https://api.ancfab.com/api/business-central/sales-orders',
    perPage: perPage,
    prevPageUrl: resolvedPrevPageUrl,
    to: data.isEmpty ? null : ((currentPage - 1) * perPage) + data.length,
    total: total ?? data.length,
  );
}

class FakeSalesOrderLinesDataSource implements SalesOrderLinesDataSource {
  FakeSalesOrderLinesDataSource({
    this.page,
    this.error,
    this.pendingFuture,
    this.pageBuilder,
  });

  /// Returned from [fetchPage] when set (and [pageBuilder] is not).
  final PaginatedResponse<BusinessCentralSalesOrderLine>? page;

  /// When set, thrown from [fetchPage] instead of returning a page.
  final Object? error;

  /// When set, awaited instead of resolving immediately — lets a test
  /// observe the loading state before controlling exactly when/how the
  /// call completes.
  final Future<PaginatedResponse<BusinessCentralSalesOrderLine>>? pendingFuture;

  /// When set, called with the requested page number to build a response —
  /// lets a test simulate real multi-page navigation without a live API.
  final PaginatedResponse<BusinessCentralSalesOrderLine> Function(int page)?
  pageBuilder;

  int callCount = 0;
  final List<int> requestedPages = [];

  @override
  Future<PaginatedResponse<BusinessCentralSalesOrderLine>> fetchPage({
    required int page,
    int perPage = 25,
  }) async {
    callCount++;
    requestedPages.add(page);
    if (pendingFuture != null) return pendingFuture!;
    if (error != null) throw error!;
    if (pageBuilder != null) return pageBuilder!(page);
    return this.page ?? samplePage();
  }
}
