import 'package:flutter/material.dart';

import '../models/support_region.dart';
import '../theme/app_colors.dart';

/// Horizontally scrollable row of selectable region pills for the Support
/// screen, so adding more regions later never causes the row to wrap or
/// overflow on narrow phones.
class SupportRegionSelector extends StatelessWidget {
  const SupportRegionSelector({
    super.key,
    required this.regions,
    required this.selectedRegionId,
    required this.onRegionSelected,
  });

  final List<SupportRegionData> regions;
  final SupportRegionId selectedRegionId;
  final ValueChanged<SupportRegionId> onRegionSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final region in regions) ...[
            _RegionPill(
              key: ValueKey('support-region-${region.id.name}'),
              label: region.displayName,
              selected: region.id == selectedRegionId,
              onTap: () => onRegionSelected(region.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RegionPill extends StatelessWidget {
  const _RegionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryNavy : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primaryNavy : AppColors.border,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textNavy,
            ),
          ),
        ),
      ),
    );
  }
}
