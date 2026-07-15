import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single labeled section within the Invoice Information card: an
/// uppercase secondary eyebrow label (e.g. "BILLED TO", "DUE DATE",
/// "PAYMENT METHOD") followed by its content.
class InvoiceInfoSection extends StatelessWidget {
  const InvoiceInfoSection({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.grayText,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
