import 'package:flutter/material.dart';

import '../models/fabric_order.dart';
import '../models/fabric_order_detail.dart';
import '../services/mock_orders_service.dart';
import '../theme/app_colors.dart';
import '../widgets/fabric_specs_sheet.dart';
import '../widgets/price_breakdown_card.dart';
import '../widgets/status_badge.dart';

/// Order Detail screen for a single Fabric Order: breadcrumb + order
/// summary, an Order Items card (hosting the Fabric Specs action), the
/// Order History card, and the Price Breakdown card with the Invoice
/// action.
///
/// TODO: Replace mock order detail fetching with the real Order Detail API
/// once the endpoint is confirmed. All fetching on this screen is
/// mock/frontend-only until then.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    MockOrdersService? ordersService,
  }) : ordersService = ordersService ?? const MockOrdersService();

  /// [FabricOrder.orderId] of the order to load (e.g. "#ORD-8829").
  final String orderId;

  /// Orders query service/repository boundary. Defaults to the mock
  /// implementation; overridable so tests can inject a fake.
  final MockOrdersService ordersService;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final MockOrdersService _ordersService = widget.ordersService;

  FabricOrderDetail? _detail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrderDetail();
  }

  /// Fetches mock Order Detail data (order summary, price breakdown, and
  /// fabric specs) through the [MockOrdersService] repository boundary.
  ///
  /// TODO: Replace mock order detail fetching with the real Order Detail
  /// API once the endpoint is confirmed.
  Future<void> _loadOrderDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await _ordersService.fetchOrderDetail(widget.orderId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load order details.';
        _isLoading = false;
      });
    }
  }

  Future<void> _retryLoadOrderDetail() async {
    await _loadOrderDetail();
  }

  /// Opens the Fabric Specs bottom sheet for the loaded order's mock fabric
  /// specs.
  ///
  /// Frontend-only and temporary: no PDF/API-backed fabric spec source
  /// exists yet.
  ///
  /// TODO: Confirm final Fabric Specs behavior with product/backend team:
  /// PDF download, modal, or separate screen.
  void _openFabricSpecs() {
    final detail = _detail;
    if (detail == null) return;
    showFabricSpecsSheet(context, detail.fabricSpecs);
  }

  /// Handles the Invoice button tap on the Price Breakdown card.
  ///
  /// No Invoice Details screen/route exists yet in this app (the current
  /// Invoices screen is a placeholder list, not a per-order detail view),
  /// so this shows a safe placeholder snackbar instead of navigating.
  ///
  /// TODO: Navigate to Invoice Details once the invoice details screen/
  /// route and API contract are confirmed.
  void _openInvoice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invoice details coming soon')),
    );
  }

  /// Handles the Order History action tap.
  ///
  /// No order status history/timeline data model, modal, or screen exists
  /// yet anywhere in this app — there is no "Invoice Payment Timeline"
  /// pattern to reuse either, since the Invoice action above is itself just
  /// a placeholder snackbar with no real timeline screen behind it. So this
  /// shows a safe placeholder snackbar instead of a fake timeline/screen.
  ///
  /// TODO: Confirm final Order History behavior with product/backend team:
  /// timeline modal, separate screen, or a shared pattern with Invoice
  /// details (once that exists) — then wire up real order status history
  /// data.
  void _openOrderHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order history coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textNavy,
      elevation: 0,
      leading: IconButton(
        key: const ValueKey('order-detail-menu-button'),
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Back',
        // No navigation drawer/menu content is defined yet for this screen,
        // so the menu affordance falls back to simple back navigation.
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const Text('Order Detail'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text(
              'IL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        key: ValueKey('order-detail-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return _buildErrorState();
    }
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBreadcrumb(detail.order),
          const SizedBox(height: 12),
          _buildOrderHeader(detail.order),
          const SizedBox(height: 16),
          _buildOrderItemsCard(detail),
          const SizedBox(height: 16),
          _buildOrderHistoryCard(),
          const SizedBox(height: 16),
          PriceBreakdownCard(
            breakdown: detail.priceBreakdown,
            onInvoicePressed: _openInvoice,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.dangerRed,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unable to load order details.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _retryLoadOrderDetail,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // Breadcrumb: "Orders > ORD-XXXX". The "Orders" segment pops back to the
  // Orders list screen this screen was pushed from.
  Widget _buildBreadcrumb(FabricOrder order) {
    return Row(
      children: [
        GestureDetector(
          key: const ValueKey('order-detail-breadcrumb-orders'),
          onTap: () => Navigator.of(context).maybePop(),
          child: const Text(
            'Orders',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '>',
            style: TextStyle(fontSize: 12.5, color: AppColors.grayText),
          ),
        ),
        Expanded(
          child: Text(
            displayOrderId(order.orderId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.grayText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderHeader(FabricOrder order) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayOrderId(order.orderId),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textNavy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Placed on ${order.date}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.grayText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusBadge(status: order.status),
      ],
    );
  }

  // Order Items card: fabric summary row plus the Fabric Specs action.
  Widget _buildOrderItemsCard(FabricOrderDetail detail) {
    final order = detail.order;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ORDER ITEMS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.grayText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.texture_rounded,
                  color: AppColors.grayText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.fabricTag,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textNavy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.meters,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.grayText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          _buildFabricSpecsAction(),
        ],
      ),
    );
  }

  // Compact "FABRIC SPECS" link/action, consistent with the Order Items
  // section it belongs to. Opens the Fabric Specs bottom sheet; see
  // [_openFabricSpecs] for the (temporary, frontend-only) behavior.
  Widget _buildFabricSpecsAction() {
    return Material(
      key: const ValueKey('order-detail-fabric-specs-button'),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _openFabricSpecs,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: AppColors.primaryNavy,
              ),
              SizedBox(width: 8),
              Text(
                'FABRIC SPECS',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.primaryNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Order History card: bordered card matching the Order Items/Price
  // Breakdown cards' style, hosting a single "ORDER HISTORY" action.
  //
  // Frontend-only and temporary: see [_openOrderHistory] for why this is a
  // placeholder rather than a real timeline modal/screen.
  Widget _buildOrderHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ORDER HISTORY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.grayText,
            ),
          ),
          const SizedBox(height: 8),
          _buildOrderHistoryAction(),
        ],
      ),
    );
  }

  // Compact "ORDER HISTORY" link/action, styled consistently with the
  // Fabric Specs action above. See [_openOrderHistory] for the current
  // (temporary, frontend-only) placeholder behavior.
  Widget _buildOrderHistoryAction() {
    return Material(
      key: const ValueKey('order-detail-order-history-button'),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _openOrderHistory,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 18,
                color: AppColors.primaryNavy,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'VIEW ORDER TIMELINE',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.grayText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
