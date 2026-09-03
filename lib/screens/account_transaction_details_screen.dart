import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/account_transaction.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';
import '../utils/date_time_format.dart';
import '../utils/responsive.dart';
import '../widgets/client_brand_title.dart';

/// Transaction Details screen for a single [AccountTransaction] selected
/// from the Account Balance screen's Quick History list.
///
/// Frontend-only: displays only the fields already present on the
/// [AccountTransaction] passed in, with no separate fetch.
///
/// TODO(api): Fetch full transaction details from the account-transactions
/// endpoint once its request and response contract is confirmed, instead of
/// relying solely on the summary fields passed from Quick History.
class AccountTransactionDetailsScreen extends StatelessWidget {
  const AccountTransactionDetailsScreen({super.key, required this.transaction});

  final AccountTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == AccountTransactionType.credit;
    final isNeutral = transaction.type == AccountTransactionType.neutral;
    final amountColor = isNeutral
        ? AppColors.textNavy
        : (isCredit ? AppColors.darkTeal : AppColors.darkRedBrown);
    final reference = transaction.reference?.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ResponsiveMaxWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const ValueKey('account-transaction-details-card'),
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
                        transaction.label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textNavy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isNeutral
                            ? formatCurrency(
                                transaction.amount,
                                currencyCode: transaction.currencyCode,
                              )
                            : formatSignedCurrency(transaction.amount),
                        key: const ValueKey(
                          'account-transaction-details-amount',
                        ),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: amountColor,
                        ),
                      ),
                      if (!isNeutral) ...[
                        const SizedBox(height: 4),
                        Text(
                          isCredit
                              ? context.t('accountTransaction.credit')
                              : context.t('accountTransaction.debit'),
                          key: const ValueKey(
                            'account-transaction-details-type',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: amountColor,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _DetailRow(
                        label: context.t('accountTransaction.date'),
                        value: formatDateOnly(transaction.occurredAt),
                      ),
                      if (reference != null && reference.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _DetailRow(
                          label: context.t('accountTransaction.reference'),
                          value: reference,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textNavy,
      elevation: 0,
      leading: IconButton(
        key: const ValueKey('account-transaction-details-menu-button'),
        icon: const Icon(Icons.menu_rounded),
        tooltip: context.t('common.back'),
        // No navigation drawer/menu content is defined yet for this
        // screen, so the menu affordance falls back to simple back
        // navigation, matching AccountBalanceScreen's convention.
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(context.t('accountTransaction.title')),
      actions: const [
        Padding(
          padding: EdgeInsetsDirectional.only(end: 16),
          child: ClientBrandTitle(
            badgeOnly: true,
            badgeSize: 32,
            badgeFontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// One label/value row in the Transaction Details card.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.grayText),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textNavy,
            ),
          ),
        ),
      ],
    );
  }
}
