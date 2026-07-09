import 'fabric_order.dart';

/// A single page of Fabric Orders returned by the Orders query boundary
/// (currently `MockOrdersService.fetchOrders`, later the real Orders API).
///
/// This shape is designed to map directly onto a typical paginated API
/// response (`items`/`totalCount`/`page`/`pageSize` plus next/previous
/// convenience flags) so swapping the mock service for a real one later
/// shouldn't require changing this model.
class PaginatedFabricOrders {
  const PaginatedFabricOrders({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  /// Orders for the current [page] only (not the full matching result set).
  final List<FabricOrder> items;

  /// Total number of orders matching the query, across all pages.
  final int totalCount;

  /// Current 1-based page number.
  final int page;

  /// Number of orders requested per page.
  final int pageSize;

  final bool hasNextPage;
  final bool hasPreviousPage;

  /// Total number of pages for [totalCount] items at [pageSize] per page.
  /// Always at least 1 so "Page 1 of 1" is shown instead of "Page 1 of 0"
  /// when there are no matching orders.
  int get totalPages =>
      totalCount == 0 ? 1 : (totalCount / pageSize).ceil();

  /// Empty result, used as a safe initial/placeholder value before the
  /// first fetch resolves.
  static const empty = PaginatedFabricOrders(
    items: [],
    totalCount: 0,
    page: 1,
    pageSize: 10,
    hasNextPage: false,
    hasPreviousPage: false,
  );
}
