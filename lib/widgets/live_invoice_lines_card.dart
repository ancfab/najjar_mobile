import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/business_central/business_central_invoice_line.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';

/// Live-data invoice line-items card for [InvoiceDetailsScreen]'s live path
/// (see `InvoiceDetailsScreen.liveInvoiceLines`).
///
/// Shows only fields the confirmed invoices contract documents for one
/// selected invoice's lines: item number, description, quantity, unit
/// price, amount, and VAT-inclusive amount, plus the customer number/name
/// shared by every line of the same invoice. [subtotal]/[totalInclVat] are
/// plain arithmetic sums of each line's own `Amount`/`Amount_Including_VAT`
/// — not an invented tax rate or rule — so they can never drift from the
/// figures already on the confirmed lines.
///
/// Deliberately does not attempt status, due date, payment method, Payment
/// Timeline, Logistics, Internal Notes, billed address/email, or a
/// separate currency symbol — none of those exist on the confirmed
/// invoice-line contract; see `InvoiceDetailsScreen`'s live-path doc
/// comment for why those sections are hidden entirely rather than shown
/// with mock values.
class LiveInvoiceLinesCard extends StatelessWidget {
  const LiveInvoiceLinesCard({super.key, required this.lines});

  /// All lines of one selected invoice (already grouped/selected by
  /// `selectLatestInvoiceLines`) — every line must share the same
  /// `Document_No`.
  final List<BusinessCentralInvoiceLine> lines;

  @override
  Widget build(BuildContext context) {
    final subtotal = lines.fold<double>(0, (sum, line) => sum + line.amount);
    final totalInclVat = lines.fold<double>(
      0,
      (sum, line) => sum + line.amountIncludingVat,
    );
    final first = lines.first;

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
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          for (final line in lines) ...[
            _buildLineRow(context, line),
            if (line != lines.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          _buildTotalRow(
            context.t('invoiceWidgets.subtotal'),
            formatPlainAmount(subtotal),
          ),
          const SizedBox(height: 6),
          _buildTotalRow(
            context.t('invoiceWidgets.totalAmount'),
            formatPlainAmount(totalInclVat),
            emphasize: true,
          ),
        ],
      ),
    );
  }

  Widget _buildLineRow(BuildContext context, BusinessCentralInvoiceLine line) {
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
