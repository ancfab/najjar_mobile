import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/order_price_breakdown.dart';
import '../theme/app_colors.dart';

/// Navy Price Breakdown card shown on the Order Detail screen: subtotal,
/// shipping, VAT, total amount, and a green Invoice action button.
class PriceBreakdownCard extends StatelessWidget {
  const PriceBreakdownCard({
    super.key,
    required this.breakdown,
    required this.onInvoicePressed,
  });

  final OrderPriceBreakdown breakdown;

  /// Called when the Invoice button is tapped. See the Order Detail
  /// screen's handler for the current placeholder-vs-real-navigation
  /// behavior.
  final VoidCallback onInvoicePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('priceBreakdown.heading'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 14),
          _buildRow(context.t('priceBreakdown.subtotal'), breakdown.subtotal),
          const SizedBox(height: 10),
          _buildRow(context.t('priceBreakdown.shipping'), breakdown.shipping),
          const SizedBox(height: 10),
          _buildRow(context.t('priceBreakdown.vat'), breakdown.vat),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white24),
          const SizedBox(height: 12),
          _buildRow(
            context.t('priceBreakdown.totalAmount'),
            breakdown.totalAmount,
            emphasized: true,
          ),
          const SizedBox(height: 16),
          _buildInvoiceButton(context),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool emphasized = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasized ? 15 : 13.5,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              color: emphasized ? Colors.white : Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: emphasized ? 20 : 14,
                fontWeight: FontWeight.bold,
                color: emphasized ? AppColors.mint : Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceButton(BuildContext context) {
    return Material(
      key: const ValueKey('price-breakdown-invoice-button'),
      color: AppColors.actionGreen,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onInvoicePressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                context.t('priceBreakdown.invoiceButton'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
