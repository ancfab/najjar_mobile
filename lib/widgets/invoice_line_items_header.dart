import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';
import 'invoice_line_items_columns.dart';

/// Light-grey four-column header row for the Invoice line-items table:
/// "ITEM DETAILS" / "QTY" / "UNIT PRICE" / "TOTAL". "ITEM DETAILS" and
/// "UNIT PRICE" wrap onto two lines at the column widths this table uses.
class InvoiceLineItemsHeader extends StatelessWidget {
  const InvoiceLineItemsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.25),
        border: const Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: kInvoiceItemDetailsColumnFlex,
            child: _label(context.t('invoiceWidgets.itemDetails')),
          ),
          const SizedBox(width: kInvoiceColumnGap),
          Expanded(
            flex: kInvoiceQuantityColumnFlex,
            child: _label(
              context.t('invoiceWidgets.qty'),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: kInvoiceColumnGap),
          Expanded(
            flex: kInvoiceUnitPriceColumnFlex,
            child: _label(
              context.t('invoiceWidgets.unitPrice'),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: kInvoiceColumnGap),
          Expanded(
            flex: kInvoiceTotalColumnFlex,
            child: _label(
              context.t('invoiceWidgets.total'),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String label, {TextAlign textAlign = TextAlign.start}) {
    return Text(
      label,
      textAlign: textAlign,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        height: 1.25,
        color: AppColors.grayText,
      ),
    );
  }
}
