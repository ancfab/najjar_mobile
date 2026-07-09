import '../data/mock_orders_data.dart';
import '../models/fabric_order.dart';
import '../models/fabric_order_detail.dart';
import '../models/fabric_order_filter.dart';
import '../models/paginated_fabric_orders.dart';

/// Supplies, filters, and paginates the Fabric Orders list for the Orders
/// screen.
///
/// This is the single service/repository boundary the Orders screen calls
/// through — it never reads [kMockFabricOrders] or applies filtering/
/// pagination logic itself, so the underlying data source (mock vs. real
/// API) can change without touching the screen.
///
/// TODO: Replace mock orders data with backend Orders list API once the
/// endpoint is confirmed (sorting is also still to be defined).
class MockOrdersService {
  const MockOrdersService();

  /// Fetches a single paginated, filtered/searched page of Fabric Orders
  /// for [filter] (status, date range, fabric type, free-text search, page,
  /// and page size).
  ///
  /// TODO: Replace mock paginated orders fetch with the real Orders API
  /// once endpoint, request parameters, response shape, authentication
  /// requirements, and pagination strategy are confirmed.
  ///
  /// Expected future API query parameters (documented here only — no
  /// backend endpoint exists yet, so nothing below is sent anywhere):
  ///  - page
  ///  - pageSize
  ///  - status
  ///  - dateFrom
  ///  - dateTo
  ///  - fabricType
  ///  - searchText
  Future<PaginatedFabricOrders> fetchOrders(FabricOrderFilter filter) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final matched = kMockFabricOrders
        .where((order) => _matchesFilter(order, filter))
        .toList();
    return _paginate(matched, filter);
  }

  /// Returns the distinct fabric type/category values available for the
  /// Fabric Type filter section.
  ///
  /// TODO: Confirm the official fabric type/category values with the
  /// backend/API team before connecting live data.
  List<String> fetchFabricTypes() => kMockFabricTypes;

  /// Fetches mock Order Detail data (the order itself, its price breakdown,
  /// and its fabric specs) for the Order Detail screen, keyed by
  /// [FabricOrder.orderId].
  ///
  /// This is frontend-only: the price breakdown and fabric specs are
  /// derived from the matching mock [FabricOrder] (see
  /// [buildMockPriceBreakdown] / [buildMockFabricSpecs]) rather than a real
  /// order detail endpoint. Throws a [StateError] if no mock order matches
  /// [orderId], which the Order Detail screen surfaces as its normal
  /// error/retry state.
  ///
  /// TODO: Replace mock price breakdown values with the real order detail
  /// API once subtotal, shipping, VAT, total amount, currency, and invoice
  /// availability fields are confirmed.
  /// TODO: Replace mock fabric specs with real fabric specification fields
  /// once the backend/API response shape is confirmed.
  Future<FabricOrderDetail> fetchOrderDetail(String orderId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final order = kMockFabricOrders.firstWhere(
      (candidate) => candidate.orderId == orderId,
      orElse: () => throw StateError('Order $orderId not found'),
    );
    return FabricOrderDetail(
      order: order,
      priceBreakdown: buildMockPriceBreakdown(order),
      fabricSpecs: buildMockFabricSpecs(order),
    );
  }

  /// Slices an already status/date/fabricType/search-matched [matched]
  /// list down to the single page requested by [filter.page]/
  /// [filter.pageSize]. [filter.page] is clamped to a valid page number so
  /// an out-of-range page (e.g. after a filter change shrinks the result
  /// set) can never index out of bounds.
  ///
  /// TODO: Once the Orders API supports server-side pagination, the server
  /// is expected to return only the requested page directly, and this
  /// client-side slicing can be removed.
  PaginatedFabricOrders _paginate(
    List<FabricOrder> matched,
    FabricOrderFilter filter,
  ) {
    final totalCount = matched.length;
    final pageSize = filter.pageSize;
    final totalPages = totalCount == 0 ? 1 : (totalCount / pageSize).ceil();
    final page = filter.page < 1
        ? 1
        : (filter.page > totalPages ? totalPages : filter.page);
    final startIndex = (page - 1) * pageSize;
    final endIndex = (startIndex + pageSize) > totalCount
        ? totalCount
        : startIndex + pageSize;
    final items = startIndex >= totalCount
        ? const <FabricOrder>[]
        : matched.sublist(startIndex, endIndex);
    return PaginatedFabricOrders(
      items: items,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
      hasNextPage: endIndex < totalCount,
      hasPreviousPage: page > 1,
    );
  }

  bool _matchesFilter(FabricOrder order, FabricOrderFilter filter) {
    if (filter.status != null && order.status != filter.status) {
      return false;
    }
    if (filter.fabricType != null && order.fabricType != filter.fabricType) {
      return false;
    }
    if (!_matchesDateRange(order, filter)) return false;
    if (!_matchesSearchText(order, filter.searchText)) return false;
    return true;
  }

  /// Evaluates the selected [DateRangeFilter] preset (or the custom
  /// start/end bounds) against [order]'s date.
  bool _matchesDateRange(FabricOrder order, FabricOrderFilter filter) {
    switch (filter.dateRange) {
      case DateRangeFilter.all:
        return true;
      case DateRangeFilter.last7Days:
        return _isWithinPastDays(order.orderDate, 7);
      case DateRangeFilter.last30Days:
        return _isWithinPastDays(order.orderDate, 30);
      case DateRangeFilter.custom:
        return _isWithinCustomRange(
          order.orderDate,
          filter.customStartDate,
          filter.customEndDate,
        );
    }
  }

  bool _isWithinPastDays(DateTime date, int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.subtract(Duration(days: days - 1));
    final orderDay = DateTime(date.year, date.month, date.day);
    return !orderDay.isBefore(cutoff) && !orderDay.isAfter(today);
  }

  /// Matches [date] against an optional custom start/end range. If only one
  /// bound is set, the range is treated as open-ended on the other side; if
  /// neither is set, every date matches — this must never throw, even for
  /// an incomplete or empty custom selection.
  bool _isWithinCustomRange(DateTime date, DateTime? start, DateTime? end) {
    final day = DateTime(date.year, date.month, date.day);
    if (start != null) {
      final startDay = DateTime(start.year, start.month, start.day);
      if (day.isBefore(startDay)) return false;
    }
    if (end != null) {
      final endDay = DateTime(end.year, end.month, end.day);
      if (day.isAfter(endDay)) return false;
    }
    return true;
  }

  /// Matches free-text [searchText] against order ID, fabric tag, fabric
  /// type, status label, and display date — case-insensitive substring
  /// match. Blank search text always matches.
  ///
  /// TODO: Replace mock order search with the backend order search endpoint
  /// once the API contract is confirmed. The backend endpoint is expected
  /// to accept a `q` (or similar) query parameter alongside the same
  /// status/date/fabricType filter parameters, rather than scanning the
  /// full mock list client-side as done here.
  bool _matchesSearchText(FabricOrder order, String searchText) {
    final query = searchText.trim().toLowerCase();
    if (query.isEmpty) return true;
    return order.orderId.toLowerCase().contains(query) ||
        order.fabricTag.toLowerCase().contains(query) ||
        order.fabricType.toLowerCase().contains(query) ||
        orderStatusLabel(order.status).toLowerCase().contains(query) ||
        order.date.toLowerCase().contains(query);
  }
}
