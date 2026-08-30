import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/credit_utilization_data.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';

/// Bordered white card showing Available/Used Credit rows, each with a
/// progress bar derived from [CreditUtilizationData]'s figures (see its
/// doc comment — the denominator is `availableCredit + usedCredit`, not a
/// separate credit-limit field, since none is returned by customer-details).
///
/// Reusable: takes its data through the constructor rather than reading a
/// model directly, matching the Invoice Details cards' convention.
class CreditUtilizationCard extends StatelessWidget {
  const CreditUtilizationCard({
    super.key,
    required this.data,
    this.currencyCode,
  });

  final CreditUtilizationData data;

  /// The display currency for [data]'s figures — passed in by the caller
  /// (Home's already-loaded `CurrentBalanceAmount.currencyCode`, ultimately
  /// from ledger-entries' `Currency_Code`); this card never resolves it
  /// itself. `null` (not yet resolved, or every contributing ledger entry
  /// had a blank `Currency_Code`) renders `formatCurrencyOrUnknown`'s "?"
  /// fallback, never a guessed code.
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
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
          Text(
            context.t('creditUtilization.heading'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 18),
          _CreditRow(
            key: const ValueKey('credit-utilization-available-row'),
            label: context.t('creditUtilization.availableCredit'),
            amount: data.availableCredit,
            ratio: data.availableCreditRatio,
            currencyCode: currencyCode,
            barColor: AppColors.darkTeal,
          ),
          const SizedBox(height: 18),
          _CreditRow(
            key: const ValueKey('credit-utilization-used-row'),
            label: context.t('creditUtilization.usedCredit'),
            amount: data.usedCredit,
            ratio: data.usedCreditRatio,
            currencyCode: currencyCode,
            barColor: AppColors.darkRedBrown,
          ),
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
    required this.currencyCode,
    required this.barColor,
  });

  final String label;
  final double amount;

  /// Fraction of total credit this row represents, already clamped to
  /// `0..1` by [CreditUtilizationData].
  final double ratio;
  final String? currencyCode;
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
              formatCurrencyOrUnknown(amount, currencyCode: currencyCode),
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
          key: const ValueKey('credit-utilization-progress-bar'),
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
