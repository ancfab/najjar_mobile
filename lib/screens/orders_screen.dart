import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/fabric_order.dart';
import '../models/fabric_order_filter.dart';
import '../models/paginated_fabric_orders.dart';
import '../services/mock_orders_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/order_card.dart';
import '../widgets/order_filter_sheet.dart';
import 'order_detail_screen.dart';

/// Frontend-only status filter passed in from other screens (e.g. the Home
/// dashboard's "Active Orders" metric card).
///
/// TODO: "active" does not map onto a single confirmed [OrderStatus] yet
/// (Delivered/Shipped/Processing are the only confirmed values). Until the
/// backend/API team confirms what "active" means, opening the screen with
/// this filter simply lands on the unfiltered "All" view below.
enum OrderStatusFilter { all, active }

/// Fabric Orders list screen for the Indigo Loom client portal.
///
/// TODO: Replace mock orders/service with the real Orders API once the
/// endpoint is confirmed. All fetching, filtering, and status handling on
/// this screen is mock/frontend-only until then.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    this.filter = OrderStatusFilter.all,
    MockOrdersService? ordersService,
  }) : ordersService = ordersService ?? const MockOrdersService();

  final OrderStatusFilter filter;

  /// Orders query service/repository boundary. Defaults to the mock
  /// implementation; overridable so tests can inject a fake (e.g. one that
  /// throws) without touching real mock data or the screen's own logic.
  final MockOrdersService ordersService;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final MockOrdersService _ordersService = widget.ordersService;

  PaginatedFabricOrders? _result;
  bool _isLoading = true;
  String? _error;

  // Combined status/date-range/fabric-type/search/page/pageSize query. See
  // [MockOrdersService.fetchOrders] for the matching + pagination logic
  // that will later map to backend query parameters.
  FabricOrderFilter _filter = const FabricOrderFilter();

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Fetches Fabric Orders for the current [_filter] through the
  /// [MockOrdersService] repository boundary. Used for the initial load
  /// and for every filter/search/pagination change and retry — the screen
  /// never filters or paginates data itself.
  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _ordersService.fetchOrders(_filter);
      if (!mounted) return;
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.t('orders.unableToLoad');
        _isLoading = false;
      });
    }
  }

  /// Refreshes the current query (filters/search/page all preserved) on
  /// pull-to-refresh, without swapping the list out for the loading
  /// skeleton — the [RefreshIndicator] spinner is enough feedback on its
  /// own, and this keeps the previously loaded page visible if the refresh
  /// fails.
  Future<void> refreshFabricOrders() async {
    try {
      final result = await _ordersService.fetchOrders(_filter);
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.t('orders.unableToRefresh'));
    }
  }

  /// Retries the current query (filters, search text, and page are left
  /// untouched — they are never cleared automatically after an error).
  Future<void> retryLoadFabricOrders() async {
    await _loadOrders();
  }

  /// Applies [transform] to the current filter and re-fetches. Any change
  /// to filters or search text resets pagination back to page 1 (per
  /// [resetPage], true by default); pure pagination changes (Previous/
  /// Next) pass `resetPage: false` so the requested page is preserved.
  void _updateFilter(
    FabricOrderFilter Function(FabricOrderFilter current) transform, {
    bool resetPage = true,
  }) {
    setState(() {
      final updated = transform(_filter);
      _filter = resetPage ? updated.copyWith(page: 1) : updated;
    });
    _loadOrders();
  }

  // Opens the filter bottom sheet, seeded with the current filter
  // selections, and applies whatever the user confirms (Apply or Reset).
  // Search text is preserved across filter changes since it has its own
  // header entry point.
  Future<void> _openFilterSheet() async {
    final fabricTypes = _ordersService.fetchFabricTypes();
    final result = await showModalBottomSheet<FabricOrderFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => OrderFilterSheet(
        initialFilter: _filter,
        fabricTypeOptions: fabricTypes,
      ),
    );
    if (result == null || !mounted) return;
    _updateFilter((current) => result.copyWith(searchText: current.searchText));
  }

  void _clearStatusFilter() {
    _updateFilter((f) => f.copyWith(clearStatus: true));
  }

  void _clearDateRangeFilter() {
    _updateFilter(
      (f) => f.copyWith(
        dateRange: DateRangeFilter.all,
        clearCustomStartDate: true,
        clearCustomEndDate: true,
      ),
    );
  }

  void _clearFabricTypeFilter() {
    _updateFilter((f) => f.copyWith(clearFabricType: true));
  }

  // Resets both the filter sheet selections and any active search text,
  // returning the Orders list to the unfiltered mock data on page 1.
  void _resetAllFiltersAndSearch() {
    _searchController.clear();
    _updateFilter((_) => const FabricOrderFilter());
  }

  void _openSearch() {
    setState(() => _isSearching = true);
  }

  void _closeSearch() {
    setState(() => _isSearching = false);
    _searchController.clear();
    _updateFilter((f) => f.copyWith(searchText: ''));
  }

  void _clearSearchText() {
    _searchController.clear();
    _updateFilter((f) => f.copyWith(searchText: ''));
    _searchFocusNode.requestFocus();
  }

  // TODO: Debounce this once wired to the real Orders API so every
  // keystroke doesn't trigger its own backend request — client-side mock
  // filtering can afford to re-query on every change.
  void _onSearchTextChanged(String value) {
    _updateFilter((f) => f.copyWith(searchText: value));
  }

  void _goToPreviousPage() {
    final result = _result;
    if (result == null || !result.hasPreviousPage) return;
    _updateFilter((f) => f.copyWith(page: result.page - 1), resetPage: false);
  }

  void _goToNextPage() {
    final result = _result;
    if (result == null || !result.hasNextPage) return;
    _updateFilter((f) => f.copyWith(page: result.page + 1), resetPage: false);
  }

  // Opens the Order Detail screen for a tapped order card. Order Detail
  // data (price breakdown, fabric specs) is loaded there via the same mock
  // [MockOrdersService], keyed off [FabricOrder.orderId] — this is a
  // temporary mock-only navigation/data-loading path until a real Order
  // Detail API exists.
  void _openOrderDetail(FabricOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(
          orderId: order.orderId,
          ordersService: _ordersService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        toolbarHeight: 68,
        titleSpacing: 0,
        title: ClampedTextScale(
          child: _isSearching ? _buildSearchField() : _buildHeaderTitle(),
        ),
        actions: [
          if (_isSearching)
            TextButton(
              key: const ValueKey('orders-search-cancel'),
              onPressed: _closeSearch,
              child: Text(
                context.t('orders.cancelSearch'),
                style: const TextStyle(
                  color: AppColors.textNavy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            IconButton(
              key: const ValueKey('orders-search-open'),
              icon: const Icon(Icons.search_rounded),
              tooltip: context.t('orders.searchOrdersTooltip'),
              onPressed: _openSearch,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: refreshFabricOrders,
          child: ResponsiveMaxWidth(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildPageIntro()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildFilterBar()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  sliver: _buildOrdersSliver(),
                ),
                if (_shouldShowResultsChrome())
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverToBoxAdapter(child: _buildPaginationFooter()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Client Portal header: small brand/logo mark, "Indigo Loom" eyebrow, and
  // the large "Client Portal" title. Replaces the search field only while
  // [_isSearching] is true.
  Widget _buildHeaderTitle() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryNavy,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text(
            'IL',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Indigo Loom',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: AppColors.grayText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                context.t('orders.clientPortalTitle'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textNavy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      key: const ValueKey('orders-search-field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: context.t('orders.searchHint'),
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.grayText),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('orders-search-clear'),
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: context.t('orders.clearSearchTooltip'),
                onPressed: _clearSearchText,
              ),
      ),
      onChanged: _onSearchTextChanged,
    );
  }

  Widget _buildPageIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('orders.globalLogisticsEyebrow'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppColors.grayText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.t('orders.fabricOrdersTitle'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
          ),
        ),
      ],
    );
  }

  // Filter entry point (centered full-width outlined bar) + active-filter
  // chips row underneath. Status/date range/fabric type are edited via the
  // [OrderFilterSheet]; each active chip here can also be cleared
  // individually without reopening the sheet.
  Widget _buildFilterBar() {
    final chips = _buildActiveFilterChips();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOpenFilterButton(),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: IntrinsicHeight(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chip in chips) ...[
                      chip,
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOpenFilterButton() {
    final count = _filter.activeFilterCount;
    final isActive = count > 0;
    return Material(
      key: const ValueKey('orders-open-filter-button'),
      color: isActive ? AppColors.primaryNavy : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openFilterSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? AppColors.primaryNavy : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 16,
                color: isActive ? Colors.white : AppColors.textNavy,
              ),
              const SizedBox(width: 8),
              Text(
                isActive
                    ? context.t(
                        'orders.filterButtonWithCount',
                        params: {'count': '$count'},
                      )
                    : context.t('orders.filterButton'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : AppColors.textNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActiveFilterChips() {
    final chips = <Widget>[];
    if (_filter.status != null) {
      chips.add(
        _activeFilterChip(
          key: const ValueKey('active-filter-status'),
          label: localizedOrderStatusLabel(context, _filter.status!),
          onClear: _clearStatusFilter,
        ),
      );
    }
    if (_filter.dateRange != DateRangeFilter.all) {
      chips.add(
        _activeFilterChip(
          key: const ValueKey('active-filter-date-range'),
          label: dateRangeFilterLabel(context, _filter.dateRange),
          onClear: _clearDateRangeFilter,
        ),
      );
    }
    if (_filter.fabricType != null) {
      chips.add(
        _activeFilterChip(
          key: const ValueKey('active-filter-fabric-type'),
          label: _filter.fabricType!,
          onClear: _clearFabricTypeFilter,
        ),
      );
    }
    return chips;
  }

  Widget _activeFilterChip({
    required Key key,
    required String label,
    required VoidCallback onClear,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.gradientNavyStart.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.gradientNavyStart.withValues(alpha: 0.3),
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.gradientNavyStart,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(10),
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.gradientNavyStart,
            ),
          ),
        ],
      ),
    );
  }

  // Whether to show the "Showing X of Y orders" counter and Previous/Next
  // pagination controls around the list: only once a query has actually
  // resolved with matches, never while loading/erroring/empty.
  bool _shouldShowResultsChrome() {
    return !_isLoading && _error == null && (_result?.totalCount ?? 0) > 0;
  }

  // Switches between loading skeleton, error+retry, empty, and loaded list
  // states for the orders section.
  Widget _buildOrdersSliver() {
    if (_isLoading) {
      return SliverToBoxAdapter(child: _buildLoadingSkeleton());
    }
    if (_error != null) {
      return SliverToBoxAdapter(child: _buildErrorState());
    }

    final items = _result?.items ?? const [];
    if (items.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyState());
    }

    return SliverList.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => OrderCard(
        order: items[index],
        onTap: () => _openOrderDetail(items[index]),
      ),
    );
  }

  /// Skeleton placeholder mimicking [OrderCard]'s layout (thumbnail box
  /// plus stacked text lines), shown while an orders query — initial load,
  /// filter/search change, pagination, or retry — is in flight.
  Widget _buildLoadingSkeleton() {
    Widget skeletonLine({double width = double.infinity, double height = 10}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    Widget skeletonCard() {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.border.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  skeletonLine(width: 100),
                  const SizedBox(height: 8),
                  skeletonLine(width: 70, height: 8),
                  const SizedBox(height: 10),
                  skeletonLine(width: 140),
                  const SizedBox(height: 10),
                  skeletonLine(width: 60, height: 8),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('orders-loading-skeleton'),
      children: List.generate(3, (_) => skeletonCard()),
    );
  }

  // Pagination footer: "Showing X of Y orders" on the left and compact
  // Previous/Next icon buttons on the right, with a small "Page X of Y"
  // indicator underneath. Reflects the current page's item count and the
  // total matching count for [_filter], so it stays in sync whenever
  // filters, search, or pagination change.
  //
  // TODO: Confirm final pagination UX with product/backend team:
  // Previous/Next controls vs infinite scroll.
  Widget _buildPaginationFooter() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                context.t(
                  'orders.showingCount',
                  params: {
                    'shown': '${result.items.length}',
                    'total': '${result.totalCount}',
                  },
                ),
                key: const ValueKey('orders-results-counter'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grayText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _paginationIconButton(
              key: const ValueKey('orders-page-previous'),
              icon: Icons.chevron_left_rounded,
              onPressed: result.hasPreviousPage ? _goToPreviousPage : null,
            ),
            const SizedBox(width: 6),
            _paginationIconButton(
              key: const ValueKey('orders-page-next'),
              icon: Icons.chevron_right_rounded,
              onPressed: result.hasNextPage ? _goToNextPage : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.t(
            'orders.pageOf',
            params: {
              'page': '${result.page}',
              'totalPages': '${result.totalPages}',
            },
          ),
          key: const ValueKey('orders-page-indicator'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.grayText,
          ),
        ),
      ],
    );
  }

  Widget _paginationIconButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        shape: const CircleBorder(),
        foregroundColor: enabled ? AppColors.primaryNavy : AppColors.grayText,
        side: BorderSide(
          color: enabled ? AppColors.primaryNavy : AppColors.border,
        ),
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Transform.flip(
        flipX: Directionality.of(context) == TextDirection.rtl,
        child: Icon(icon, size: 18),
      ),
    );
  }

  // Error state with a retry action, shown when the orders fail to load and
  // no previously loaded data is available to fall back on.
  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.dangerRed,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? context.t('orders.unableToLoad'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grayText),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: retryLoadFabricOrders,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
            ),
            child: Text(context.t('common.retry')),
          ),
        ],
      ),
    );
  }

  // Shown when there are no orders to display, either because the mock
  // dataset is empty or the current filter/search has no matches.
  Widget _buildEmptyState() {
    final hasActiveCriteria = !_filter.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, color: AppColors.grayText, size: 28),
          const SizedBox(height: 8),
          Text(
            hasActiveCriteria
                ? context.t('orders.noOrdersFiltered')
                : context.t('orders.noOrdersYet'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grayText),
          ),
          if (hasActiveCriteria) ...[
            const SizedBox(height: 12),
            TextButton(
              key: const ValueKey('orders-empty-reset-filters'),
              onPressed: _resetAllFiltersAndSearch,
              child: Text(context.t('orders.resetFilters')),
            ),
          ],
        ],
      ),
    );
  }
}
