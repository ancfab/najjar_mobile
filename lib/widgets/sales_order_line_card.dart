import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/business_central/sales_order_line.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import '../utils/currency.dart';

/// Card summarizing a single [BusinessCentralSalesOrderLine] on the Orders
/// screen.
///
/// Deliberately shows only fields the confirmed sales-orders contract
/// documents (`Document_No`, `Line_No`, `No.`/item number, `Description`,
/// `Quantity`, `Unit_Price`, `Amount`) — no thumbnail, status badge, fabric
/// tag, or date, since none of those exist on this endpoint and this widget
/// must never fabricate them (see `FabricOrder`'s equivalent, mock-only
/// fields, which this widget intentionally does not mirror).
class SalesOrderLineCard extends StatelessWidget {
  const SalesOrderLineCard({super.key, required this.line, this.onTap});

  final BusinessCentralSalesOrderLine line;

  /// Called when the card is tapped. Left `null` (the default, non-
  /// interactive) since no live Order Detail view exists yet for a
  /// sales-order line — see `OrdersScreen`.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: _buildCardContent(context),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.elevatedCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line.documentNo,
                  style: AppTypography.sectionTitle.copyWith(
                    color: AppColors.textNavy,
                  ),
                  maxLines: 1,
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
          const SizedBox(height: 4),
          Text(
            line.description,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textNavy),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            context.t('salesOrderLine.itemNo', params: {'itemNo': line.itemNo}),
            style: const TextStyle(fontSize: 12, color: AppColors.grayText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    formatPlainAmount(line.amount),
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
    );
  }
}
