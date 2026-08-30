import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';
import '../utils/currency.dart';

/// Dark-navy hero card showing the global account balance, its percentage
/// change vs. the prior period, and an Export PDF action. Rendered at the
/// top of [AccountBalanceScreen], above the Credit Utilization card.
///
/// Reusable: takes its data through the constructor rather than reading a
/// model directly, matching the Invoice Details cards' convention (e.g.
/// `PaymentTimeline`, `InvoiceLogisticsStatusCard`).
class AccountBalanceHeroCard extends StatelessWidget {
  const AccountBalanceHeroCard({
    super.key,
    required this.balance,
    required this.onExportPdf,
    this.isExporting = false,
    this.currencyCode,
  });

  final double balance;

  final VoidCallback onExportPdf;

  /// Whether the account statement PDF is currently being generated. Shows
  /// a spinner in place of the icon and relabels the button "Generating...",
  /// and disables it so a second export can't be triggered mid-flight.
  final bool isExporting;

  /// The display currency for [balance] — passed in by the caller (Home's
  /// already-loaded `CurrentBalanceAmount.currencyCode`, ultimately from
  /// ledger-entries' `Currency_Code`); this card never resolves it itself.
  /// `null` (not yet resolved, or every contributing ledger entry had a
  /// blank `Currency_Code`) renders `formatCurrencyOrUnknown`'s "?"
  /// fallback, never a guessed code.
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('account-balance-hero-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          const _DecorativeBalanceShapes(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('accountBalance.globalAccountBalance'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Color(0xFFB7B8E3),
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  formatCurrencyOrUnknown(balance, currencyCode: currencyCode),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ElevatedButton(
                  key: const ValueKey('account-balance-export-pdf-button'),
                  onPressed: isExporting ? null : onExportPdf,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gradientNavyStart,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.gradientNavyStart,
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isExporting
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              key: ValueKey(
                                'account-balance-export-pdf-loading',
                              ),
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                context.t('accountBalance.generatingPdf'),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.upload_file_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                context.t('accountBalance.exportPdf'),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Faint outlined balance-related icons in the card's background, purely
/// decorative — kept subtle (low opacity) so they never compete with the
/// balance figure/text in front of them.
class _DecorativeBalanceShapes extends StatelessWidget {
  const _DecorativeBalanceShapes();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.08,
          child: Stack(
            children: const [
              Positioned(
                right: -28,
                top: -28,
                child: Icon(
                  Icons.donut_large_rounded,
                  size: 140,
                  color: Colors.white,
                ),
              ),
              Positioned(
                right: 36,
                bottom: -36,
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 96,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
