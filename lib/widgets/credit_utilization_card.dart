import 'package:flutter/material.dart';

import '../models/credit_utilization_data.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';

/// Bordered white card showing Available/Used Credit rows (each with a
/// progress bar calculated from [CreditUtilizationData]'s figures) and an
/// optional credit-limit-change note.
///
/// Reusable: takes its data through the constructor rather than reading a
/// model directly, matching the Invoice Details cards' convention.
class CreditUtilizationCard extends StatelessWidget {
  const CreditUtilizationCard({super.key, required this.data});

  final CreditUtilizationData data;

  @override
  Widget build(BuildContext context) {
    final note = data.creditLimitChangeNote?.trim();

    return Container(
      key: const ValueKey('credit-utilization-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Credit Utilization',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 18),
          _CreditRow(
            key: const ValueKey('credit-utilization-available-row'),
            label: 'Available Credit',
            amount: data.availableCredit,
            ratio: data.availableCreditRatio,
            barColor: AppColors.darkTeal,
          ),
          const SizedBox(height: 18),
          _CreditRow(
            key: const ValueKey('credit-utilization-used-row'),
            label: 'Used Credit',
            amount: data.usedCredit,
            ratio: data.usedCreditRatio,
            barColor: AppColors.darkRedBrown,
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              key: const ValueKey('credit-utilization-note'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                note,
                style: const TextStyle(fontSize: 13, color: AppColors.grayText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One label/amount row plus its progress bar, shared by the Available
/// Credit and Used Credit rows.
class _CreditRow extends StatelessWidget {
  const _CreditRow({
    super.key,
    required this.label,
    required this.amount,
    required this.ratio,
    required this.barColor,
  });

  final String label;
  final double amount;

  /// Fraction of total credit this row represents, already clamped to
  /// `0..1` by [CreditUtilizationData].
  final double ratio;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.grayText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCurrency(amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 8,
                    width: double.infinity,
                    color: AppColors.background,
                  ),
                  Container(
                    height: 8,
                    width: constraints.maxWidth * ratio,
                    color: barColor,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
