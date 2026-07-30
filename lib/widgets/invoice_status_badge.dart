import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../theme/app_colors.dart';

/// Small navy pill showing an invoice's status in uppercase white text
/// (e.g. "PAID"). Used on the Invoice Details screen's information card.
class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({super.key, required this.status});

  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        invoiceStatusLabel(context, status).toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}
