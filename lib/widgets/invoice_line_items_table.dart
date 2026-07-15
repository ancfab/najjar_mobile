import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_colors.dart';
import 'invoice_line_item_row.dart';
import 'invoice_line_items_header.dart';
import 'invoice_totals_section.dart';

/// Invoice line-items table: header row, one row per [Invoice.items] entry
/// (separated by thin dividers), and the Subtotal/Tax/Total Amount summary.
///
/// Shown as a continuation of the Invoice Information card, directly below
/// the Payment Method section — not a separate card.
class InvoiceLineItemsTable extends StatelessWidget {
  const InvoiceLineItemsTable({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final items = invoice.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InvoiceLineItemsHeader(),
        for (var i = 0; i < items.length; i++) ...[
          InvoiceLineItemRow(item: items[i]),
          if (i != items.length - 1)
            const Divider(height: 1, color: AppColors.border),
        ],
        const SizedBox(height: 6),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 14),
        InvoiceTotalsSection(invoice: invoice),
      ],
    );
  }
}
