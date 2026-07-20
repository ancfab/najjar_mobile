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
    this.image,
  });

  final String initials;
  final VoidCallback? onTap;
  final double diameter;

  /// When set, shown in place of [initials] — e.g. the signed-in user's
  /// avatar photo. Falls back to [initials] whenever this is null (no
  /// avatar set, or it failed to load), preserving this badge's existing
  /// size/shape/styling either way.
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: AppColors.primaryNavy,
          shape: BoxShape.circle,
          image: image != null
              ? DecorationImage(image: image!, fit: BoxFit.cover)
              : null,
        ),
        alignment: Alignment.center,
        child: image != null
            ? null
            : Text(
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
