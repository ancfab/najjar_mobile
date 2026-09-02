import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';
import '../utils/date_time_format.dart';

/// Two tappable date fields ("From"/"To") for the Balance History card,
/// replacing the retired 30 Days/90 Days/1 Year preset selector. Matches
/// `OrderFilterSheet`'s existing custom-date-field styling/convention
/// (`_dateField`) so the app has one consistent look for a date-picker
/// field rather than a second competing style.
///
/// Purely a controlled input: [from]/[to] are owned by the caller
/// (`AccountBalanceScreen`), which also owns validating and normalizing a
/// newly picked date (date-only, From never after To) before passing the
/// updated value back down — this widget only constrains what a single
/// `showDatePicker` call can return via [firstDate]/[lastDate], as a
/// first line of defense against picking an invalid date in the UI itself.
class BalanceHistoryDateRangePicker extends StatelessWidget {
  const BalanceHistoryDateRangePicker({
    super.key,
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
  });

  final DateTime from;
  final DateTime to;
  final ValueChanged<DateTime> onFromChanged;
  final ValueChanged<DateTime> onToChanged;

  /// Earliest date either picker will ever offer — matches
  /// `OrderFilterSheet`'s existing custom-date-range floor
  /// (`DateTime(now.year - 5)`) so this app has one consistent "how far
  /// back can a date picker go" convention rather than a second one.
  DateTime _earliestSelectableDate() {
    final now = DateTime.now();
    return DateTime(now.year - 5);
  }

  Future<void> _pickFrom(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from,
      firstDate: _earliestSelectableDate(),
      // Never after the current To date — see the class doc comment; the
      // caller still normalizes defensively on top of this.
      lastDate: to,
    );
    if (picked != null) onFromChanged(picked);
  }

  Future<void> _pickTo(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: to,
      // Never before the current From date, and never a future date (no
      // confirmed product requirement allows one) — see the class doc
      // comment; the caller still normalizes defensively on top of this.
      firstDate: from,
      lastDate: now,
    );
    if (picked != null) onToChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DateField(
            fieldKey: const ValueKey('balance-history-from-field'),
            label: context.t('balanceHistory.fromLabel'),
            value: formatDateOnly(from),
            onTap: () => _pickFrom(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DateField(
            fieldKey: const ValueKey('balance-history-to-field'),
            label: context.t('balanceHistory.toLabel'),
            value: formatDateOnly(to),
            onTap: () => _pickTo(context),
          ),
        ),
      ],
    );
  }
}

/// One bordered, tappable date field — visually identical to
/// `OrderFilterSheet._dateField`.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: fieldKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.grayText),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textNavy,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: AppColors.grayText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
