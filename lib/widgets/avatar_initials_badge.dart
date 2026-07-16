import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small rounded badge showing a user's initials (e.g. "AS"), used in the
/// header in place of a photo avatar when only a name is available. See
/// `userInitials` for how the initials are derived.
class AvatarInitialsBadge extends StatelessWidget {
  const AvatarInitialsBadge({
    super.key,
    required this.initials,
    this.onTap,
    this.diameter = 32,
  });

  final String initials;
  final VoidCallback? onTap;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: const BoxDecoration(
          color: AppColors.primaryNavy,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
