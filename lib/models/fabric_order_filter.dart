import 'fabric_order.dart';

/// Date-range presets available in the Orders filter sheet.
enum DateRangeFilter { all, last7Days, last30Days, custom }

/// Display label for a [DateRangeFilter] value, shared by the filter sheet
/// and the active-filter chip on the Orders screen.
String dateRangeFilterLabel(DateRangeFilter value) {
  switch (value) {
    case DateRangeFilter.all:
      return 'All dates';
    case DateRangeFilter.last7Days:
      return 'Last 7 days';
    case DateRangeFilter.last30Days:
      return 'Last 30 days';
    case DateRangeFilter.custom:
      return 'Custom range';
  }
}

/// Typed filter/query object for the Fabric Orders list: status, date
/// range, fabric type, free-text search, and pagination (page/pageSize).
///
/// This is currently applied client-side against the mock orders dataset
/// via `MockOrdersService.fetchOrders`. Once the Orders API is available,
/// this same shape is expected to map onto backend query parameters
/// (e.g. `status`, `dateFrom`/`dateTo`, `fabricType`, `searchText`, `page`,
/// `pageSize`) instead of being evaluated locally after a full fetch.
class FabricOrderFilter {
  const FabricOrderFilter({
    this.status,
    this.dateRange = DateRangeFilter.all,
    this.customStartDate,
    this.customEndDate,
    this.fabricType,
    this.searchText = '',
    this.page = 1,
    this.pageSize = 10,
  });

  final OrderStatus? status;
  final DateRangeFilter dateRange;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final String? fabricType;
  final String searchText;

  /// 1-based current page. Expected to map onto a future `page` API query
  /// parameter.
  final int page;

  /// Orders requested per page. Expected to map onto a future `pageSize`
  /// API query parameter.
  final int pageSize;

  /// Count of active filter *sections* (status, date range, fabric type).
  /// Search text is intentionally excluded — it has its own UI entry point
  /// and isn't represented in the filter sheet's badge/count.
  int get activeFilterCount {
    var count = 0;
    if (status != null) count++;
    if (dateRange != DateRangeFilter.all) count++;
    if (fabricType != null) count++;
    return count;
  }

  /// Whether no filter or search criteria are active at all.
  bool get isEmpty =>
      status == null &&
      dateRange == DateRangeFilter.all &&
      fabricType == null &&
      searchText.isEmpty;

  FabricOrderFilter copyWith({
    OrderStatus? status,
    bool clearStatus = false,
    DateRangeFilter? dateRange,
    DateTime? customStartDate,
    bool clearCustomStartDate = false,
    DateTime? customEndDate,
    bool clearCustomEndDate = false,
    String? fabricType,
    bool clearFabricType = false,
    String? searchText,
    int? page,
    int? pageSize,
  }) {
    return FabricOrderFilter(
      status: clearStatus ? null : (status ?? this.status),
      dateRange: dateRange ?? this.dateRange,
      customStartDate: clearCustomStartDate
          ? null
          : (customStartDate ?? this.customStartDate),
      customEndDate: clearCustomEndDate
          ? null
          : (customEndDate ?? this.customEndDate),
      fabricType: clearFabricType ? null : (fabricType ?? this.fabricType),
      searchText: searchText ?? this.searchText,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}
