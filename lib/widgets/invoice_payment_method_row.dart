import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';

/// Teal bank icon plus the bold payment method line (e.g. "Bank Transfer
/// (Ending ...4492)"), shown in the Invoice Information card's Payment
/// Method section. Wraps instead of overflowing on narrow devices.
class InvoicePaymentMethodRow extends StatelessWidget {
  const InvoicePaymentMethodRow({
    super.key,
    required this.method,
    required this.maskedReference,
  });

  final String method;
  final String maskedReference;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.mint.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.account_balance_outlined,
            color: AppColors.darkTeal,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.t(
              'invoiceWidgets.paymentEnding',
              params: {'method': method, 'reference': maskedReference},
            ),
            softWrap: true,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
        ),
      ],
    );
  }
}
