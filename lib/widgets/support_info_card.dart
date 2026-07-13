import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Generic bordered information card used by the Support screen's Corporate
/// Office and Direct Hotline sections: a small icon chip, an all-caps
/// label, and free-form content below that can grow vertically when text
/// wraps.
class SupportInfoCard extends StatelessWidget {
  const SupportInfoCard({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
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
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: AppColors.textNavy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.grayText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
