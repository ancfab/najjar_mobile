import 'package:flutter/material.dart';

import '../models/balance_history_range.dart';
import '../theme/app_colors.dart';

/// Compact segmented selector for the Balance History chart's time range
/// (30 Days / 90 Days / 1 Year). The selected segment uses the dark-navy
/// treatment shared with [CustomBottomNav]'s selected tab.
class BalanceHistoryRangeSelector extends StatelessWidget {
  const BalanceHistoryRangeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final BalanceHistoryRange selected;
  final ValueChanged<BalanceHistoryRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('balance-history-range-selector'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final range in BalanceHistoryRange.values)
            Expanded(child: _buildSegment(range)),
        ],
      ),
    );
  }

  Widget _buildSegment(BalanceHistoryRange range) {
    final isSelected = range == selected;
    return GestureDetector(
      key: ValueKey('balance-history-range-${range.name}'),
      onTap: () => onChanged(range),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          range.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.grayText,
          ),
        ),
      ),
    );
  }
}
