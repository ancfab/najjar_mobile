import 'package:flutter/widgets.dart';

import '../localization/translations.dart';

/// Time-range options for the Balance History chart's segmented selector.
enum BalanceHistoryRange { thirtyDays, ninetyDays, oneYear }

extension BalanceHistoryRangeLabel on BalanceHistoryRange {
  /// English label used only where no [BuildContext] is available (e.g.
  /// the account statement PDF export) — UI display goes through
  /// [localizedLabel] instead.
  String get label {
    switch (this) {
      case BalanceHistoryRange.thirtyDays:
        return '30 Days';
      case BalanceHistoryRange.ninetyDays:
        return '90 Days';
      case BalanceHistoryRange.oneYear:
        return '1 Year';
    }
  }

  /// Localized display label matching the segmented selector's button
  /// text exactly (e.g. `"30 Days"`).
  String localizedLabel(BuildContext context) {
    switch (this) {
      case BalanceHistoryRange.thirtyDays:
        return context.t('balanceHistoryRange.days30');
      case BalanceHistoryRange.ninetyDays:
        return context.t('balanceHistoryRange.days90');
      case BalanceHistoryRange.oneYear:
        return context.t('balanceHistoryRange.year1');
    }
  }
}
