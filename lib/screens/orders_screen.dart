import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/business_central/paginated_response.dart';
import '../models/business_central/sales_order_line.dart';
import '../services/business_central_error_mapper.dart';
import '../services/sales_order_lines_data_source.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/sales_order_line_card.dart';
import 'order_detail_screen.dart';

/// Frontend-only status filter passed in from other screens (e.g. the Home
/// dashboard's "Active Orders" metric card).
///
/// TODO(api): The confirmed sales-orders contract has no status field at
/// all, so this can never be honored against live data — accepted here only
/// so callers (e.g. `HomeScreen`) don't need to change; the screen always
/// shows the unfiltered live list regardless of this value.
enum OrderStatusFilter { all, active }

/// Sales-order-line list screen for the Indigo Loom client portal.
///
/// Shows the live `GET /api/business-central/sales-orders` result: one row
/// per sales-order line (never grouped by `Document_No`), paginated with
/// explicit Previous/Next controls at a fixed page size.
///
/// TODO(api): The previous mock-backed status/date-range/fabric-type filter
/// sheet and free-text search are not shown here — none of their criteria
/// exist on the confirmed sales-orders contract (no status, date, or fabric
/// type field; the endpoint accepts only `page`/`per_page`), so keeping that
/// UI would mean either silently doing nothing or filtering only the
/// current page's up-to-100 rows while claiming completeness across all
/// unseen pages. Both are unacceptable; see `MockOrdersService`/
/// `FabricOrder`/`OrderFilterSheet`, which remain in the codebase unused by
/// this screen in case a future confirmed contract supports server-side
/// filtering.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    this.filter = OrderStatusFilter.all,
    this.salesOrderLinesSource,
  });

  final OrderStatusFilter filter;

  /// Sales-order-lines data seam. Defaults (lazily, in State) to
  /// [LiveSalesOrderLinesDataSource] — the live Business Central
  /// sales-orders endpoint; overridable so tests can inject a fake.
  final SalesOrderLinesDataSource? salesOrderLinesSource;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

/// Fixed page size requested for every page of this screen's session —
/// preserved across Previous/Next so the effective page size never drifts,
/// per the confirmed pagination rules.
const int _kOrdersPerPage = 25;

class _OrdersScreenState extends State<OrdersScreen> {
  late final SalesOrderLinesDataSource _salesOrderLinesSource =
      widget.salesOrderLinesSource ?? LiveSalesOrderLinesDataSource();

  PaginatedResponse<BusinessCentralSalesOrderLine>? _result;

  /// Also doubles as the duplicate-request guard in [_loadPage] — starts
  /// `false` so the very first [_loadPage] call from [initState] is never
  /// blocked by its own not-yet-started loading state; [_loadPage] itself
  /// flips this to `true` (synchronously, before its first `await`) so the
  /// initial loading skeleton is still showing by the first build.
  bool _isLoading = false;
  BusinessCentralOutcome? _errorOutcome;

  /// `true` only when the most recent failure was not a
  /// [BusinessCentralFailureException] (e.g. an unexpected exception) —
  /// shown with the same neutral retry copy as every outcome other than
  /// "temporarily unavailable", mirroring [_errorOutcome]'s sibling usage
  /// on the Home screen's Current Balance/Last Payment cards.
  bool _hasUnknownError = false;

  /// The page this screen currently shows (or is loading/retrying) —
  /// distinct from [_result]'s own `currentPage`, which only updates once a
  /// request actually succeeds, so Previous/Next/retry always know the
  /// *intended* page even while a request for it is still in flight or just
  /// failed.
  int _requestedPage = 1;

  /// Bumped at the start of every [_loadPage] call, so a stale in-flight
  /// request (e.g. a slow Next that resolves after a faster subsequent
  /// Previous already started) can recognize itself as superseded and
  /// discard its result instead of corrupting fresher state.
  int _requestGeneration = 0;

  /// Guards against opening more than one Order Detail screen from a rapid
  /// double-tap on the same (or a different) row before the first push has
  /// even started animating.
  bool _isOpeningOrderDetail = false;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  /// Opens Order Detail for [documentNo] — the sales order's confirmed
  /// identifier, never [BusinessCentralSalesOrderLine.lineNo] alone. Rows
  /// sharing the same `Document_No` all open the same Order Detail screen,
  /// which is correct: they are lines of the same order.
  void _openOrderDetail(String documentNo) {
    if (_isOpeningOrderDetail) return;
    _isOpeningOrderDetail = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(documentNo: documentNo),
          ),
        )
        .then((_) {
          if (mounted) setState(() => _isOpeningOrderDetail = false);
        });
  }

  /// Fetches [page] of sales-order lines. Used for the initial load, every
  /// Previous/Next tap, pull-to-refresh, and retry — the screen never pages
  /// or filters data itself. Ignored while a request is already in flight
  /// (duplicate-tap guard), and superseded by a newer call if one starts
  /// before this one resolves (stale-response guard via
  /// [_requestGeneration]).
  Future<void> _loadPage(int page) async {
    if (_isLoading) return;
    final generation = ++_requestGeneration;
    setState(() {
      _isLoading = true;
      _requestedPage = page;
      _errorOutcome = null;
      _hasUnknownError = false;
    });
    try {
      final result = await _salesOrderLinesSource.fetchPage(
        page: page,
        perPage: _kOrdersPerPage,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } on SessionExpiredException {
      // The centralized session coordinator has already cleared the
      // session and is navigating to Login — show nothing here.
    } on BusinessCentralFailureException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _errorOutcome = error.outcome;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _hasUnknownError = true;
        _isLoading = false;
      });
    }
  }

  /// Refreshes the currently displayed (or intended) page on pull-to-
  /// refresh, without swapping the list out for the loading skeleton — the
  /// [RefreshIndicator] spinner is enough feedback on its own, and this
  /// keeps the previously loaded page visible if the refresh fails.
  Future<void> refreshSalesOrderLines() => _loadPage(_requestedPage);

  /// Retries the page that was actually intended (the one Previous/Next/the
  /// initial load was trying to show), never silently resetting to page 1.
  Future<void> retryLoadSalesOrderLines() => _loadPage(_requestedPage);

  bool get _hasPreviousPage {
    final result = _result;
    return result != null && result.currentPage > 1;
  }

  bool get _hasNextPage {
    final result = _result;
    if (result == null) return false;
    // Both confirmed disabling conditions: current_page == last_page, or
    // next_page_url == null.
    return result.currentPage < result.lastPage && result.nextPageUrl != null;
  }

  void _goToPreviousPage() {
    if (_isLoading || !_hasPreviousPage) return;
    _loadPage(_result!.currentPage - 1);
  }

  void _goToNextPage() {
    if (_isLoading || !_hasNextPage) return;
    _loadPage(_result!.currentPage + 1);
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
        title: ClampedTextScale(child: _buildHeaderTitle()),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: refreshSalesOrderLines,
          child: ResponsiveMaxWidth(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildPageIntro()),
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
  // the large "Client Portal" title.
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

  // Whether to show the "Showing X-Y of Z order lines" counter and
  // Previous/Next pagination controls around the list: only once a query
  // has actually resolved with matches, never while loading/erroring/empty.
  bool _shouldShowResultsChrome() {
    return !_isLoading &&
        _errorOutcome == null &&
        !_hasUnknownError &&
        (_result?.data.isNotEmpty ?? false);
  }

  // Switches between loading skeleton, error+retry, empty, and loaded list
  // states for the sales-order-lines section.
  Widget _buildOrdersSliver() {
    if (_isLoading) {
      return SliverToBoxAdapter(child: _buildLoadingSkeleton());
    }
    if (_errorOutcome != null || _hasUnknownError) {
      return SliverToBoxAdapter(child: _buildErrorState());
    }

    final lines = _result?.data ?? const [];
    if (lines.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyState());
    }

    return SliverList.separated(
      itemCount: lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => SalesOrderLineCard(
        key: ValueKey(lines[index].identity),
        line: lines[index],
        onTap: () => _openOrderDetail(lines[index].documentNo),
      ),
    );
  }

  /// Skeleton placeholder mimicking [SalesOrderLineCard]'s layout, shown
  /// while a sales-order-lines query — initial load, pagination, or retry —
  /// is in flight. Never shows mock rows.
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
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            skeletonLine(width: 120),
            const SizedBox(height: 8),
            skeletonLine(width: 200, height: 8),
            const SizedBox(height: 8),
            skeletonLine(width: 90, height: 8),
            const SizedBox(height: 12),
            skeletonLine(width: 140, height: 8),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('orders-loading-skeleton'),
      children: List.generate(3, (_) => skeletonCard()),
    );
  }

  // Pagination footer: "Showing X-Y of Z order lines" on the left and
  // compact Previous/Next icon buttons on the right, with a small
  // "Page X of Y" indicator underneath.
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
                _lineCounterText(result),
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
              onPressed: (!_isLoading && _hasPreviousPage)
                  ? _goToPreviousPage
                  : null,
            ),
            const SizedBox(width: 6),
            _paginationIconButton(
              key: const ValueKey('orders-page-next'),
              icon: Icons.chevron_right_rounded,
              onPressed: (!_isLoading && _hasNextPage) ? _goToNextPage : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.t(
            'orders.pageOf',
            params: {
              'page': '${result.currentPage}',
              'totalPages': '${result.lastPage}',
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

  /// Builds the "Showing X-Y of Z order lines" counter directly from the
  /// backend's own `from`/`to`/`total` fields — never derived by
  /// multiplying `current_page * per_page`. `from`/`to` are only ever
  /// `null` when `data` is empty, a case this screen shows the empty state
  /// for instead (see [_shouldShowResultsChrome]); this still falls back to
  /// a safe "0 of 0" rendering rather than ever interpolating a literal
  /// `null` into the displayed text.
  String _lineCounterText(
    PaginatedResponse<BusinessCentralSalesOrderLine> result,
  ) {
    final from = result.from;
    final to = result.to;
    if (from == null || to == null) {
      return context.t('orders.showingZeroLineCount');
    }
    return context.t(
      'orders.showingLineCount',
      params: {'from': '$from', 'to': '$to', 'total': '${result.total}'},
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

  /// Maps [_errorOutcome] to controlled, safe user-facing copy — the
  /// backend's raw `message` is never shown directly (see
  /// `BusinessCentralOutcome`'s doc comments). [_hasUnknownError] (a
  /// non-Business-Central exception) gets the same generic copy as every
  /// outcome other than "temporarily unavailable".
  String _errorMessage() {
    return switch (_errorOutcome) {
      BusinessCentralTemporarilyUnavailable() => context.t(
        'orders.temporarilyUnavailable',
      ),
      _ => context.t('orders.unableToLoad'),
    };
  }

  // Error state with a retry action, shown when sales-order lines fail to
  // load and no previously loaded page is available to fall back on.
  Widget _buildErrorState() {
    return Container(
      key: const ValueKey('orders-error-state'),
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
            _errorMessage(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grayText),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: retryLoadSalesOrderLines,
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

  // Shown when the live sales-orders endpoint returns no rows.
  Widget _buildEmptyState() {
    return Container(
      key: const ValueKey('orders-empty-state'),
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
            context.t('orders.noOrderLinesYet'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.grayText),
          ),
        ],
      ),
    );
  }
}
