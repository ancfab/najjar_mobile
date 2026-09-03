import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/business_central/business_central_invoice_line.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';
import '../utils/date_time_format.dart';
import 'invoice_status_pill.dart';

/// Live-data invoice line-items card for [InvoiceDetailsScreen]'s live path
/// (see `InvoiceDetailsScreen.liveInvoiceLines`).
///
/// Shows every field the confirmed invoices contract documents for one
/// selected invoice's lines: item number, description, quantity, unit
/// price, amount, and VAT-inclusive amount, plus the customer number/name
/// shared by every line of the same invoice, and — when the tenant
/// publishes them (confirmed live 2026-09-03, not guaranteed present on
/// every tenant) — [InvoiceStatusPill], due date, and payment method.
/// [subtotal]/[totalInclVat] are plain arithmetic sums of each line's own
/// `Amount`/`Amount_Including_VAT` — not an invented tax rate or rule — so
/// they can never drift from the figures already on the confirmed lines.
/// Every amount is prefixed with the invoice's own `Currency_Code` (see
/// [_invoiceCurrency]) via [formatCurrencyOrUnknown] — no prefix at all when
/// every line's currency is blank/unknown, never a guessed symbol.
///
/// Deliberately does not attempt Payment Timeline, Logistics, Internal
/// Notes, billed address/email, an "Auth Code", a "Processing Node", a
/// "Compliance" indicator, or a bank-transfer reference — none of those
/// exist on the confirmed invoice-line contract; inventing them would be
/// exactly the fabricated data this app's product owner has ruled out. See
/// `InvoiceDetailsScreen`'s live-path doc comment for the full list of
/// mock-only sections hidden entirely rather than shown with fake values.
class LiveInvoiceLinesCard extends StatelessWidget {
  const LiveInvoiceLinesCard({super.key, required this.lines});

  /// All lines of one selected invoice (already grouped/selected by
  /// `selectLatestInvoiceLines`) — every line must share the same
  /// `Document_No`.
  final List<BusinessCentralInvoiceLine> lines;

  @override
  Widget build(BuildContext context) {
    final subtotal = lines.fold<double>(0, (sum, line) => sum + line.amount);
    // Falls back to a line's own Amount when Amount_Including_VAT isn't
    // published (confirmed absent on Lebanon/Iraq's real invoices page,
    // see that field's doc comment) — the real confirmed Amount, never an
    // invented VAT figure, and mathematically identical to subtotal when
    // no line publishes a VAT-inclusive amount at all.
    final totalInclVat = lines.fold<double>(
      0,
      (sum, line) => sum + (line.amountIncludingVat ?? line.amount),
    );
    final first = lines.first;
    final currencyCode = _invoiceCurrency(lines);
    final status = _firstNonBlank(lines.map((l) => l.invoiceStatus));
    final dueDate = _firstNonNull(lines.map((l) => l.dueDate));
    final paymentMethod = _firstNonBlank(lines.map((l) => l.paymentMethod));

    return Container(
      key: const ValueKey('live-invoice-lines-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('invoiceDetails.liveCustomerLabel'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppColors.grayText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${first.sellToCustomerName} (${first.sellToCustomerNo})',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textNavy,
                      ),
                    ),
                  ],
                ),
              ),
              if (status != null) InvoiceStatusPill(status: status),
            ],
          ),
          if (dueDate != null || paymentMethod != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (dueDate != null)
                  _InfoChip(
                    label: context.t('invoiceWidgets.dueDate'),
                    value: formatDateOnly(dueDate),
                  ),
                if (paymentMethod != null)
                  _InfoChip(
                    label: context.t('invoiceWidgets.paymentMethod'),
                    value: paymentMethod,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          for (final line in lines) ...[
            _buildLineRow(context, line, currencyCode),
            if (line != lines.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          _buildTotalRow(
            context.t('invoiceWidgets.subtotal'),
            formatCurrencyOrUnknown(subtotal, currencyCode: currencyCode),
          ),
          const SizedBox(height: 6),
          _buildTotalRow(
            context.t('invoiceWidgets.totalAmount'),
            formatCurrencyOrUnknown(totalInclVat, currencyCode: currencyCode),
            emphasize: true,
          ),
        ],
      ),
    );
  }

  /// The first non-blank `Currency_Code` among [lines], in order — `null`
  /// when every line's currency is blank/unknown. Every line of one
  /// invoice is expected to share one currency; this never mixes or
  /// re-derives one, only picks the first confirmed value present.
  static String? _invoiceCurrency(List<BusinessCentralInvoiceLine> lines) {
    for (final line in lines) {
      if (line.currencyCode.trim().isNotEmpty) return line.currencyCode;
    }
    return null;
  }

  static String? _firstNonBlank(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static DateTime? _firstNonNull(Iterable<DateTime?> values) {
    for (final value in values) {
      if (value != null) return value;
    }
    return null;
  }

  Widget _buildLineRow(
    BuildContext context,
    BusinessCentralInvoiceLine line,
    String? currencyCode,
  ) {
    return Column(
      key: ValueKey('live-invoice-line-${line.documentNo}-${line.lineNo}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.description,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textNavy),
        ),
        const SizedBox(height: 2),
        Text(
          context.t('salesOrderLine.itemNo', params: {'itemNo': line.itemNo}),
          style: const TextStyle(fontSize: 12, color: AppColors.grayText),
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
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCurrencyOrUnknown(line.amount, currencyCode: currencyCode),
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

  Widget _buildTotalRow(String label, String value, {bool emphasize = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 14 : 12.5,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize ? AppColors.textNavy : AppColors.grayText,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 15 : 12.5,
            fontWeight: FontWeight.w700,
            color: emphasize ? AppColors.primaryNavy : AppColors.textNavy,
          ),
        ),
      ],
    );
  }
}

/// A small "LABEL: value" pair for real, optional invoice-level info (due
/// date, payment method) — only ever rendered when the tenant published a
/// real value for it (see [LiveInvoiceLinesCard.build]).
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: AppColors.grayText),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textNavy,
            ),
          ),
        ],
      ),
    );
  }
}
