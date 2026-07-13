import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Peach-tinted "Support Hours" card, visually distinct from the neutral
/// white info cards to match the Support screen's accent styling.
class SupportHoursCard extends StatelessWidget {
  const SupportHoursCard({super.key, required this.scheduleText});

  final String scheduleText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.peach.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.peach),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.peach,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.access_time_filled_rounded,
                  size: 17,
                  color: AppColors.darkRedBrown,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'SUPPORT HOURS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.darkRedBrown,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scheduleText,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.darkRedBrown,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
