import 'package:flutter/material.dart';

import '../models/fabric_order.dart';
import '../theme/app_colors.dart';

/// Display metadata (label + colors) for a single [OrderStatus] value.
class _StatusBadgeMeta {
  const _StatusBadgeMeta(this.label, this.background, this.foreground);

  final String label;
  final Color background;
  final Color foreground;
}

/// Maps an [OrderStatus] to the label and colors [StatusBadge] renders.
///
/// TODO: Confirm the complete list of possible order statuses with the
/// backend/API team before connecting live data — the labels/colors below
/// are a temporary mock-only mapping. Any status that isn't one of the
/// confirmed values resolves to [OrderStatus.unknown] (via [mapOrderStatus])
/// and renders as a neutral "Unknown" badge instead of crashing the UI.
_StatusBadgeMeta _metaForStatus(BuildContext context, OrderStatus status) {
  final label = localizedOrderStatusLabel(context, status);
  switch (status) {
    case OrderStatus.delivered:
      return _StatusBadgeMeta(label, AppColors.mint, AppColors.darkTeal);
    case OrderStatus.shipped:
      return _StatusBadgeMeta(
        label,
        AppColors.gradientNavyStart.withValues(alpha: 0.12),
        AppColors.gradientNavyStart,
      );
    case OrderStatus.processing:
      return _StatusBadgeMeta(label, AppColors.peach, AppColors.darkRedBrown);
    case OrderStatus.unknown:
      return _StatusBadgeMeta(
        label,
        AppColors.border.withValues(alpha: 0.5),
        AppColors.grayText,
      );
  }
}

/// Small reusable pill showing an order's status with a label and color
/// style. Used on Fabric Order cards and reusable for future order detail
/// screens.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final meta = _metaForStatus(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: meta.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: meta.foreground,
        ),
      ),
    );
  }
}
