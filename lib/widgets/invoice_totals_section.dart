import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';

/// Subtotal / Tax / Total Amount summary rows shown below the Invoice
/// line-items table. All three values come from [Invoice.subtotal],
/// [Invoice.taxAmount], and [Invoice.totalAmount] — calculated on the model,
/// never duplicated here.
class InvoiceTotalsSection extends StatelessWidget {
  const InvoiceTotalsSection({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow('Subtotal', invoice.subtotal),
        const SizedBox(height: 8),
        _buildRow('Tax', invoice.taxAmount),
        const SizedBox(height: 10),
        _buildRow('Total Amount', invoice.totalAmount, emphasized: true),
      ],
    );
  }

  Widget _buildRow(String label, double amount, {bool emphasized = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasized ? 16 : 13.5,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
              color: emphasized ? AppColors.textNavy : AppColors.grayText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              formatCurrency(amount),
              maxLines: 1,
              style: TextStyle(
                fontSize: emphasized ? 18 : 14,
                fontWeight: FontWeight.bold,
                color: emphasized ? AppColors.primaryNavy : AppColors.textNavy,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
