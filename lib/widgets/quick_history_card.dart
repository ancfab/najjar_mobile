import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/account_transaction.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';

/// Bordered white card showing the Account Balance screen's Quick History
/// list: a "QUICK HISTORY" header with a "See all" chevron action, and a
/// compact tappable row per [AccountTransaction].
///
/// Reusable: takes its transactions through the constructor rather than
/// reading a service directly, matching [CreditUtilizationCard] and
/// [BalanceHistoryCard]'s convention.
class QuickHistoryCard extends StatelessWidget {
  const QuickHistoryCard({
    super.key,
    required this.transactions,
    required this.onTransactionTap,
    required this.onSeeAll,
  });

  final List<AccountTransaction> transactions;

  /// Called with the tapped transaction when a row is tapped.
  final ValueChanged<AccountTransaction> onTransactionTap;

  /// Called when the header's "See all" chevron is tapped.
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('quick-history-card'),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('quickHistory.heading'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textNavy,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('quick-history-see-all-button'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: onSeeAll,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Transform.flip(
                      flipX: Directionality.of(context) == TextDirection.rtl,
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < transactions.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _QuickHistoryRow(
              key: ValueKey('quick-history-row-${transactions[i].id}'),
              transaction: transactions[i],
              onTap: () => onTransactionTap(transactions[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tappable transaction row: a category icon in a compact rounded
/// container, the transaction label, and its right-aligned signed amount.
class _QuickHistoryRow extends StatelessWidget {
  const _QuickHistoryRow({
    super.key,
    required this.transaction,
    required this.onTap,
  });

  final AccountTransaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == AccountTransactionType.credit;
    final isNeutral = transaction.type == AccountTransactionType.neutral;
    final amountColor = isNeutral
        ? AppColors.textNavy
        : (isCredit ? AppColors.darkTeal : AppColors.darkRedBrown);
    final iconBackground = isNeutral
        ? AppColors.background
        : (isCredit
              ? AppColors.darkTeal.withValues(alpha: 0.12)
              : AppColors.background);
    final iconColor = isNeutral
        ? AppColors.grayText
        : (isCredit ? AppColors.darkTeal : AppColors.grayText);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconForCategory(transaction.category),
                  size: 18,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  transaction.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textNavy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isNeutral
                    ? formatCurrency(
                        transaction.amount,
                        currencyCode: transaction.currencyCode,
                      )
                    : formatSignedCurrency(transaction.amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconForCategory(AccountTransactionCategory category) {
  switch (category) {
    case AccountTransactionCategory.supplyPurchase:
      return Icons.inventory_2_outlined;
    case AccountTransactionCategory.deposit:
      return Icons.savings_outlined;
    case AccountTransactionCategory.serviceFee:
      return Icons.receipt_long_outlined;
    case AccountTransactionCategory.ledgerEntry:
      return Icons.article_outlined;
  }
}
