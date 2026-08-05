import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/business_central/sales_order_line.dart';
import '../services/business_central_error_mapper.dart';
import '../services/invoice_grouping.dart';
import '../services/invoice_lookup_data_source.dart';
import '../services/order_detail_data_source.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';
import '../utils/responsive.dart';
import 'invoice_details_screen.dart';

/// Order Detail screen for a single Business Central sales order,
/// identified by its confirmed `Document_No` — never a `Line_No` alone
/// (many lines share one `Document_No`; see `BusinessCentralSalesOrderLine`).
///
/// Live-backed: fetches every sales-order line for [documentNo] via
/// [orderDetailSource] (`GET /api/business-central/sales-orders?
/// document_no=...`, all required pages), and resolves the Invoice button
/// via [invoiceLookupSource] (`GET /api/business-central/invoices?
/// order_no=...`, grouped by invoice `Document_No`, highest one selected —
/// see `selectLatestInvoiceLines`).
///
/// Shows only fields the confirmed sales-orders contract documents
/// (`Document_No`, `Line_No`, item `No.`, `Description`, `Quantity`,
/// `Unit_Price`, `Amount`, `Sell_to_Customer_No`/`Name`). No status badge,
/// order date, delivery date, currency symbol, shipping, VAT, fabric type,
/// or Fabric Specs section — none of those exist on this contract, and this
/// screen must never fabricate them. The completed Order History action
/// (a localized "coming soon" placeholder — see `_openOrderHistory`) is
/// preserved unchanged; it is out of scope for this live-wiring task.
class OrderDetailScreen extends StatefulWidget {
  OrderDetailScreen({
    super.key,
    required this.documentNo,
    OrderDetailDataSource? orderDetailSource,
    InvoiceLookupDataSource? invoiceLookupSource,
  }) : orderDetailSource = orderDetailSource ?? LiveOrderDetailDataSource(),
       invoiceLookupSource =
           invoiceLookupSource ?? LiveInvoiceLookupDataSource();

  /// The sales order's confirmed `Document_No` (e.g. `"SO-24001"`) — the
  /// order identifier per the confirmed contract.
  final String documentNo;

  /// Order-line query seam. Defaults to the live Business Central
  /// sales-orders endpoint; overridable so tests can inject a fake.
  final OrderDetailDataSource orderDetailSource;

  /// Invoice-lookup seam for the Invoice button. Defaults to the live
  /// Business Central invoices endpoint; overridable so tests can inject a
  /// fake.
  final InvoiceLookupDataSource invoiceLookupSource;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final OrderDetailDataSource _orderDetailSource =
      widget.orderDetailSource;
  late final InvoiceLookupDataSource _invoiceLookupSource =
      widget.invoiceLookupSource;

  List<BusinessCentralSalesOrderLine>? _lines;

  /// Also doubles as the duplicate-request guard in [_loadOrder] — mirrors
  /// `OrdersScreen._isLoading`'s exact convention.
  bool _isLoading = false;

  /// `true` only after a successful fetch returned zero lines (the
  /// confirmed HTTP 200 + empty `data` "order not found" case) — distinct
  /// from [_errorOutcome]/[_hasUnknownError], which mean the request itself
  /// failed.
  bool _notFound = false;

  BusinessCentralOutcome? _errorOutcome;
  bool _hasUnknownError = false;

  /// Bumped at the start of every [_loadOrder] call, so a stale in-flight
  /// request (e.g. a slow initial load superseded by a retry) can recognize
  /// itself as superseded and discard its result instead of corrupting
  /// fresher state.
  int _requestGeneration = 0;

  /// Guards the Invoice button against duplicate taps while a lookup is in
  /// flight, and drives its loading-spinner state.
  bool _isResolvingInvoice = false;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  /// Fetches every sales-order line for [OrderDetailScreen.documentNo].
  /// Used for the initial load and retry. Ignored while a request is
  /// already in flight (duplicate-tap guard), and superseded by a newer
  /// call if one starts before this one resolves (stale-response guard via
  /// [_requestGeneration]).
  Future<void> _loadOrder() async {
    if (_isLoading) return;
    final generation = ++_requestGeneration;
    setState(() {
      _isLoading = true;
      _notFound = false;
      _errorOutcome = null;
      _hasUnknownError = false;
    });
    try {
      final lines = await _orderDetailSource.fetchOrder(
        documentNo: widget.documentNo,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _lines = lines;
        _notFound = lines.isEmpty;
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

  Future<void> _retryLoadOrder() => _loadOrder();

  /// Handles the Invoice button tap: looks up every invoice line related to
  /// this order (`order_no` = [OrderDetailScreen.documentNo]), groups the
  /// result by invoice `Document_No`, and opens the invoice with the
  /// highest `Document_No` (see `selectLatestInvoiceLines`). Shows a
  /// localized neutral message and stays on Order Detail when no invoice is
  /// related — never opens a mock invoice, and a failed/absent invoice
  /// lookup never affects the already-loaded order lines above it.
  Future<void> _openInvoice() async {
    if (_isResolvingInvoice) return;
    setState(() => _isResolvingInvoice = true);
    try {
      final lines = await _invoiceLookupSource.fetchInvoiceLinesForOrder(
        orderNo: widget.documentNo,
      );
      if (!mounted) return;
      final selected = selectLatestInvoiceLines(lines);
      if (selected == null) {
        _showSnackBar(context.t('orderDetail.noInvoiceAvailable'));
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailsScreen(
            invoiceNumber: selected.first.documentNo,
            liveInvoiceLines: selected,
          ),
        ),
      );
    } on SessionExpiredException {
      // The centralized session coordinator has already cleared the
      // session and is navigating to Login — show nothing here.
    } on BusinessCentralFailureException {
      if (!mounted) return;
      _showSnackBar(context.t('orderDetail.invoiceLookupFailed'));
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(context.t('orderDetail.invoiceLookupFailed'));
    } finally {
      if (mounted) setState(() => _isResolvingInvoice = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Handles the Order History action tap.
  ///
  /// The Invoice action above does push a real screen with real (live or
  /// mock) data — but no order-status-history model, field, or API exists
  /// anywhere (the confirmed sales-orders response is line-item data only,
  /// with no status/date/transition fields to build a real timeline from).
  /// This app's other unconfirmed-data actions (Account Balance's full
  /// history, Invoice's email action, Scan Stock, Home Settings) all stay a
  /// plain enabled action that shows a localized "not available yet"
  /// snackbar rather than inventing a new interaction style — this follows
  /// that same established convention. Preserved unchanged by the Order
  /// Detail API integration task; out of scope for it.
  void _openOrderHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('orderDetail.historyComingSoon'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: SafeArea(top: false, child: _buildBody()),
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
        tooltip: context.t('common.back'),
        // No navigation drawer/menu content is defined yet for this screen,
        // so the menu affordance falls back to simple back navigation.
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(context.t('orderDetail.title')),
      actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 16),
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
    if (_notFound) {
      return _buildNotFoundState();
    }
    if (_errorOutcome != null || _hasUnknownError) {
      return _buildErrorState();
    }
    final lines = _lines;
    if (lines == null || lines.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveMaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBreadcrumb(),
            const SizedBox(height: 12),
            _buildOrderHeader(lines.first),
            const SizedBox(height: 16),
            _buildOrderItemsCard(lines),
            const SizedBox(height: 16),
            _buildOrderHistoryCard(),
            const SizedBox(height: 16),
            _buildInvoiceCard(),
          ],
        ),
      ),
    );
  }

  /// Maps [_errorOutcome] to controlled, safe user-facing copy, mirroring
  /// `OrdersScreen._errorMessage`'s exact convention — the backend's raw
  /// `message` is never shown directly.
  String _errorMessage() {
    return switch (_errorOutcome) {
      BusinessCentralTemporarilyUnavailable() => context.t(
        'orderDetail.temporarilyUnavailable',
      ),
      _ => context.t('orderDetail.unableToLoad'),
    };
  }

  Widget _buildErrorState() {
    return Center(
      key: const ValueKey('order-detail-error-state'),
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
              _errorMessage(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _retryLoadOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                foregroundColor: Colors.white,
              ),
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      ),
    );
  }

  // Shown when the live sales-orders endpoint returns HTTP 200 with an
  // empty `data` array for the requested `document_no` — the confirmed
  // "order not found" case, distinct from a request failure.
  Widget _buildNotFoundState() {
    return Center(
      key: const ValueKey('order-detail-not-found'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              color: AppColors.grayText,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              context.t('orderDetail.orderNotFoundTitle'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textNavy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              context.t('orderDetail.orderNotFoundMessage'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grayText),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const ValueKey('order-detail-not-found-back'),
              onPressed: () => Navigator.of(context).maybePop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                foregroundColor: Colors.white,
              ),
              child: Text(context.t('common.back')),
            ),
          ],
        ),
      ),
    );
  }

  // Breadcrumb: "Orders > SO-24001". The "Orders" segment pops back to the
  // Orders list screen this screen was pushed from.
  Widget _buildBreadcrumb() {
    return Row(
      children: [
        GestureDetector(
          key: const ValueKey('order-detail-breadcrumb-orders'),
          onTap: () => Navigator.of(context).maybePop(),
          child: Text(
            context.t('orderDetail.breadcrumbOrders'),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Transform.flip(
            flipX: Directionality.of(context) == TextDirection.rtl,
            child: const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.grayText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            widget.documentNo,
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

  // Order header: Document_No plus the customer name/number shared by every
  // line — no status badge or order/delivery date, since neither exists on
  // the confirmed contract.
  Widget _buildOrderHeader(BusinessCentralSalesOrderLine firstLine) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.documentNo,
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
          context.t('orderDetail.customerLabel'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.grayText,
          ),
        ),
        Text(
          '${firstLine.sellToCustomerName} (${firstLine.sellToCustomerNo})',
          style: const TextStyle(fontSize: 13, color: AppColors.textNavy),
        ),
      ],
    );
  }

  // Order Items card: every returned sales-order line, shown separately
  // (never grouped/summarized into one fabric row).
  Widget _buildOrderItemsCard(List<BusinessCentralSalesOrderLine> lines) {
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
          Text(
            context.t('orderDetail.itemsHeader'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.grayText,
            ),
          ),
          const SizedBox(height: 12),
          for (final line in lines) ...[
            _buildOrderLineRow(line),
            if (line != lines.last) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOrderLineRow(BusinessCentralSalesOrderLine line) {
    return Column(
      key: ValueKey('order-detail-line-${line.identity}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                line.description,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textNavy,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.t(
                'salesOrderLine.lineNumber',
                params: {'lineNo': '${line.lineNo}'},
              ),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.grayText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          context.t('salesOrderLine.itemNo', params: {'itemNo': line.itemNo}),
          style: const TextStyle(fontSize: 12, color: AppColors.grayText),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                context.t(
                  'salesOrderLine.quantityAtPrice',
                  params: {
                    'quantity': formatPlainAmount(line.quantity),
                    'unitPrice': formatPlainAmount(line.unitPrice),
                  },
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grayText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatPlainAmount(line.amount),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryNavy,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Order History card: bordered card matching the Order Items/Invoice
  // cards' style, hosting a single "ORDER HISTORY" action. Preserved
  // unchanged — see [_openOrderHistory].
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
          Text(
            context.t('orderDetail.historyHeader'),
            style: const TextStyle(
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

  // Compact "ORDER HISTORY" link/action, unchanged from before this task —
  // see [_openOrderHistory] for the current (temporary, frontend-only)
  // placeholder behavior.
  Widget _buildOrderHistoryAction() {
    return Material(
      key: const ValueKey('order-detail-order-history-button'),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _openOrderHistory,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 18,
                color: AppColors.primaryNavy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('orderDetail.viewTimelineAction'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
              Transform.flip(
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.grayText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Invoice card: bordered card matching the Order History card's style,
  // hosting a single "VIEW INVOICE" action. See [_openInvoice] for the
  // live lookup/grouping/latest-selection behavior it triggers.
  Widget _buildInvoiceCard() {
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
          Text(
            context.t('orderDetail.invoiceHeader'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.grayText,
            ),
          ),
          const SizedBox(height: 8),
          _buildInvoiceAction(),
        ],
      ),
    );
  }

  Widget _buildInvoiceAction() {
    return Material(
      key: const ValueKey('order-detail-invoice-button'),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _isResolvingInvoice ? null : _openInvoice,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AppColors.primaryNavy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('orderDetail.viewInvoiceAction'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
              if (_isResolvingInvoice)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.grayText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
