import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_colors.dart';
import 'invoice_info_section.dart';
import 'invoice_payment_method_row.dart';
import 'invoice_status_badge.dart';

/// Bordered white card showing an invoice's key details: status/number/
/// issued date summary, Billed To, Due Date, and Payment Method.
class InvoiceInfoCard extends StatelessWidget {
  const InvoiceInfoCard({
    super.key,
    required this.invoice,
    required this.onEmailTap,
  });

  final Invoice invoice;

  /// Called when the billed-to email link is tapped. See the Invoice
  /// Details screen's handler for the current placeholder-vs-real email
  /// launching behavior.
  final VoidCallback onEmailTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryRow(),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          InvoiceInfoSection(label: 'BILLED TO', child: _buildBilledTo()),
          const SizedBox(height: 16),
          InvoiceInfoSection(
            label: 'DUE DATE',
            child: Text(
              invoice.dueDate,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.darkRedBrown,
              ),
            ),
          ),
          const SizedBox(height: 16),
          InvoiceInfoSection(
            label: 'PAYMENT METHOD',
            child: InvoicePaymentMethodRow(
              method: invoice.paymentMethod,
              maskedReference: invoice.paymentReferenceMasked,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InvoiceStatusBadge(status: invoice.status),
              const SizedBox(height: 10),
              const Text(
                'Invoice Number',
                style: TextStyle(fontSize: 12, color: AppColors.grayText),
              ),
              const SizedBox(height: 2),
              Text(
                invoice.invoiceNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryNavy,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Issued Date',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: AppColors.grayText),
              ),
              const SizedBox(height: 2),
              Text(
                invoice.issuedDate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textNavy,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBilledTo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          invoice.billedCompany,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textNavy,
          ),
        ),
        const SizedBox(height: 6),
        for (final line in invoice.billedAddressLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              line,
              style: const TextStyle(fontSize: 13, color: AppColors.grayText),
            ),
          ),
        const SizedBox(height: 6),
        GestureDetector(
          key: const ValueKey('invoice-details-billed-email'),
          onTap: onEmailTap,
          child: Text(
            invoice.billedEmail,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryNavy,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primaryNavy,
            ),
          ),
        ),
      ],
    );
  }
}
