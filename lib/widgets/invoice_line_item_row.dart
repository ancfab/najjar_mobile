import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';
import 'invoice_line_items_columns.dart';

/// A single Invoice line-item row: name/description, quantity/unit, unit
/// price, and line total — laid out in the same four columns as
/// [InvoiceLineItemsHeader]. Currency cells stay on one line (shrinking to
/// fit via [FittedBox] on narrow widths) rather than wrapping or clipping;
/// name/description wrap naturally instead.
class InvoiceLineItemRow extends StatelessWidget {
  const InvoiceLineItemRow({super.key, required this.item});

  final InvoiceLineItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: kInvoiceItemDetailsColumnFlex,
            child: _buildItemDetails(),
          ),
          const SizedBox(width: kInvoiceColumnGap),
          Expanded(flex: kInvoiceQuantityColumnFlex, child: _buildQuantity()),
          const SizedBox(width: kInvoiceColumnGap),
          Expanded(
            flex: kInvoiceUnitPriceColumnFlex,
            child: _buildAmount(
              formatCurrency(item.unitPrice),
              color: AppColors.textNavy,
              bold: false,
            ),
          ),
          const SizedBox(width: kInvoiceColumnGap),
          Expanded(
            flex: kInvoiceTotalColumnFlex,
            child: _buildAmount(
              formatCurrency(item.lineTotal),
              color: AppColors.primaryNavy,
              bold: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          softWrap: true,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textNavy,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.description,
          softWrap: true,
          style: const TextStyle(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            color: AppColors.grayText,
          ),
        ),
      ],
    );
  }

  Widget _buildQuantity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${item.quantity}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textNavy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.unit,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.grayText),
        ),
      ],
    );
  }

  Widget _buildAmount(String value, {required Color color, required bool bold}) {
    return Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
