import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/business_central/business_central_invoice_line.dart';
import '../services/business_central_error_mapper.dart';
import '../services/invoices_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import '../utils/currency.dart';
import '../utils/date_time_format.dart';
import '../utils/responsive.dart';
import '../widgets/invoice_status_pill.dart';
import 'invoice_details_screen.dart';

/// Sort order applied client-side over the invoices already fetched (see
/// [_InvoicesScreenState._sortedAndFiltered]) — never a claim about
/// ordering across pages not yet loaded.
enum _InvoiceSort { newestFirst, oldestFirst, amountHighToLow, amountLowToHigh }

/// Frontend-only status filter for the Invoices screen.
///
/// The confirmed invoice-line contract carries no per-invoice status or
/// due-date field on every tenant, so `overdue` cannot filter the list —
/// it only changes the title and shows an honest scope note (see
/// [_InvoicesScreenState]). The customer's overdue TOTAL is real, live
/// data on the Home screen's metric card (customer-details API).
enum InvoiceStatusFilter { all, overdue }

/// Live Invoices list: every posted sales invoice line for the
/// authenticated customer, fetched from `GET /api/business-central/invoices`
/// via [InvoicesService] and grouped client-side by `Document_No` (one card
/// per invoice). Tapping a card opens [InvoiceDetailsScreen]'s live
/// rendering path with that invoice's own lines — no mock/dummy data
/// anywhere on this flow.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({
    super.key,
    this.filter = InvoiceStatusFilter.all,
    this.invoicesService,
  });

  final InvoiceStatusFilter filter;

  /// Data seam. Defaults (lazily, in State) to a real, owned
  /// [InvoicesService]; overridable so tests can inject one wired to a fake
  /// client instead of real HTTP/secure storage.
  final InvoicesService? invoicesService;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

/// One invoice (all fetched lines sharing a `Document_No`), summarized for
/// its list card. Purely derived display data — never fabricated: absent
/// posting dates stay null, and the total is the exact sum of the lines'
/// `Amount_Including_VAT`.
class _InvoiceGroup {
  const _InvoiceGroup({
    required this.documentNo,
    required this.postingDate,
    required this.lines,
    required this.totalIncludingVat,
    required this.currencyCode,
    required this.invoiceStatus,
    required this.paymentMethod,
  });

  final String documentNo;
  final DateTime? postingDate;
  final List<BusinessCentralInvoiceLine> lines;
  final double totalIncludingVat;

  /// The first non-blank `Currency_Code` among [lines] — `null` when every
  /// line's currency is blank/unknown. Every line of one invoice is
  /// expected to share one currency; this never mixes or re-derives one.
  final String? currencyCode;

  /// The first non-blank `Invoice_Status` among [lines] — `null` when no
  /// line published one (see `BusinessCentralInvoiceLine.invoiceStatus`;
  /// not every tenant publishes this field). Never a fabricated status.
  final String? invoiceStatus;

  /// The first non-blank `Payment_Method` among [lines] — `null` when no
  /// line published one. Never a fabricated value.
  final String? paymentMethod;
}

enum _LoadState { loading, error, loaded }

class _InvoicesScreenState extends State<InvoicesScreen> {
  late final InvoicesService _service;
  InvoicesService? _ownedService;

  _LoadState _state = _LoadState.loading;
  List<_InvoiceGroup> _groups = const [];
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    final injected = widget.invoicesService;
    if (injected != null) {
      _service = injected;
    } else {
      final owned = InvoicesService();
      _ownedService = owned;
      _service = owned;
    }
    _loadFirstPage();
  }

  @override
  void dispose() {
    _ownedService?.close();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() => _state = _LoadState.loading);
    try {
      await _service.loadFirstPage();
      if (!mounted) return;
      setState(() {
        _groups = _groupLines(_service.lines);
        _state = _LoadState.loaded;
      });
    } on SessionExpiredException {
      // The coordinator is already navigating to Login; render nothing.
      if (mounted) setState(() => _state = _LoadState.loaded);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_service.hasNextPage) return;
    setState(() => _isLoadingMore = true);
    try {
      await _service.loadNextPage();
      if (!mounted) return;
      setState(() => _groups = _groupLines(_service.lines));
    } on SessionExpiredException {
      // Already handled centrally.
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('invoices.unableToLoadMore'))),
      );
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// Groups fetched lines by `Document_No`, then orders the resulting
  /// invoices by `Posting_Date` descending (latest date first — e.g.
  /// 2026-09-01 before 2026-08-31). A document with no known posting date
  /// at all (see `BusinessCentralInvoiceLine.postingDate`'s doc comment on
  /// why this is sometimes null/omitted live) can't be placed by date
  /// honestly, so it's kept after every dated document, in the API's own
  /// most-recently-fetched-first record order — never sorted to an
  /// arbitrary/guessed position among the dated ones.
  static List<_InvoiceGroup> _groupLines(
    List<BusinessCentralInvoiceLine> lines,
  ) {
    final byDocument = <String, List<BusinessCentralInvoiceLine>>{};
    for (final line in lines) {
      byDocument.putIfAbsent(line.documentNo, () => []).add(line);
    }
    final groups = [
      for (final entry in byDocument.entries.toList().reversed)
        _InvoiceGroup(
          documentNo: entry.key,
          postingDate: entry.value
              .map((line) => line.postingDate)
              .firstWhere((date) => date != null, orElse: () => null),
          lines: entry.value,
          // Falls back to a line's own Amount when Amount_Including_VAT
          // isn't published (confirmed absent on Lebanon/Iraq's real
          // invoices page) — see BusinessCentralInvoiceLine
          // .amountIncludingVat's doc comment; never an invented VAT figure.
          totalIncludingVat: entry.value.fold<double>(
            0,
            (sum, line) => sum + (line.amountIncludingVat ?? line.amount),
          ),
          currencyCode: _invoiceCurrency(entry.value),
          invoiceStatus: _firstNonBlank(
            entry.value.map((line) => line.invoiceStatus),
          ),
          paymentMethod: _firstNonBlank(
            entry.value.map((line) => line.paymentMethod),
          ),
        ),
    ];

    final dated = <_InvoiceGroup>[];
    final undated = <_InvoiceGroup>[];
    for (final group in groups) {
      (group.postingDate == null ? undated : dated).add(group);
    }
    // List.sort isn't guaranteed stable, but a tie (two invoices posted the
    // exact same date) has no more-precise real signal to break it with, so
    // an arbitrary stable-or-not order between them is acceptable here.
    dated.sort((a, b) => b.postingDate!.compareTo(a.postingDate!));
    return [...dated, ...undated];
  }

  /// The first non-blank `Currency_Code` among [lines], in order — `null`
  /// when every line's currency is blank/unknown.
  static String? _invoiceCurrency(List<BusinessCentralInvoiceLine> lines) {
    for (final line in lines) {
      if (line.currencyCode.trim().isNotEmpty) return line.currencyCode;
    }
    return null;
  }

  /// The first non-null, non-blank value among [values], in order — `null`
  /// when every value is absent/blank. Shared by [invoiceStatus] and
  /// [paymentMethod] grouping: every real value observed is a single
  /// per-document field repeated across a document's lines, never one that
  /// legitimately differs line-to-line.
  static String? _firstNonBlank(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  void _openInvoice(_InvoiceGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsScreen(
          invoiceNumber: group.documentNo,
          liveInvoiceLines: group.lines,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = widget.filter == InvoiceStatusFilter.overdue;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        title: Text(
          isOverdue
              ? context.t('invoices.overdueTitle')
              : context.t('invoices.title'),
        ),
      ),
      body: SafeArea(child: _buildBody(isOverdue)),
    );
  }

  Widget _buildBody(bool isOverdue) {
    switch (_state) {
      case _LoadState.loading:
        return const Center(
          child: CircularProgressIndicator(key: ValueKey('invoices-loading')),
        );
      case _LoadState.error:
        return CenteredScrollable(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                context.t('invoices.unableToLoad'),
                key: const ValueKey('invoices-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grayText),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('invoices-retry'),
                onPressed: _loadFirstPage,
                child: Text(context.t('common.retry')),
              ),
            ],
          ),
        );
      case _LoadState.loaded:
        if (_groups.isEmpty) {
          return CenteredScrollable(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                context.t('invoices.empty'),
                key: const ValueKey('invoices-empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grayText),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _loadFirstPage,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isOverdue) ...[
                Container(
                  key: const ValueKey('invoices-overdue-note'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningYellow.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    context.t('invoices.overdueScopeNote'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (final group in _groups) ...[
                _InvoiceCard(group: group, onTap: () => _openInvoice(group)),
                const SizedBox(height: 10),
              ],
              if (_service.hasNextPage)
                Center(
                  child: _isLoadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          key: const ValueKey('invoices-load-more'),
                          onPressed: _loadMore,
                          child: Text(context.t('invoices.loadMore')),
                        ),
                ),
            ],
          ),
        );
    }
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.group, required this.onTap});

  final _InvoiceGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final postingDate = group.postingDate;
    final paymentMethod = group.paymentMethod;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('invoice-card-${group.documentNo}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.elevatedCard,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLeadingIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            group.documentNo,
                            style: AppTypography.sectionTitle.copyWith(
                              color: AppColors.textNavy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InvoiceStatusPill(status: group.invoiceStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (postingDate != null) formatDateOnly(postingDate),
                        context.t(
                          'invoices.linesCount',
                          params: {'count': '${group.lines.length}'},
                        ),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.grayText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: paymentMethod == null
                              ? const SizedBox.shrink()
                              : _buildPaymentMethodChip(context, paymentMethod),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              formatCurrencyOrUnknown(
                                group.totalIncludingVat,
                                currencyCode: group.currencyCode,
                              ),
                              maxLines: 1,
                              style: AppTypography.numericValue.copyWith(
                                color: AppColors.primaryNavy,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Decorative leading icon box occupying the same slot a Fabric Order
  /// card's thumbnail photo would — real invoice data carries no image, so
  /// this is a fixed icon, never a fetched/fabricated picture.
  Widget _buildLeadingIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Icon(Icons.receipt_long_outlined, color: AppColors.grayText),
    );
  }

  /// Small tag chip showing this invoice's real `Payment_Method` — only
  /// rendered when at least one line published one (see
  /// `_InvoiceGroup.paymentMethod`), never a fabricated placeholder.
  Widget _buildPaymentMethodChip(BuildContext context, String paymentMethod) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        paymentMethod,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textNavy,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
