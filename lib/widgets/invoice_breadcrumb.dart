import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Breadcrumb shown at the top of the Invoice Details screen: "Invoices >
/// #INV-XXXX", with "Invoices" as the tappable parent-page segment and the
/// invoice number emphasized in the primary navy color as the current page.
class InvoiceBreadcrumb extends StatelessWidget {
  const InvoiceBreadcrumb({
    super.key,
    required this.invoiceNumber,
    required this.onInvoicesTap,
  });

  final String invoiceNumber;

  /// Called when the "Invoices" segment is tapped.
  final VoidCallback onInvoicesTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          key: const ValueKey('invoice-details-breadcrumb-invoices'),
          onTap: onInvoicesTap,
          child: const Text(
            'Invoices',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.grayText,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.grayText,
          ),
        ),
        Expanded(
          child: Text(
            invoiceNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
      ],
    );
  }
}
