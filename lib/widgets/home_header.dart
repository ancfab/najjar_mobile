import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.userName,
    this.onAvatarTap,
    this.onSettingsTap,
  });

  final String userName;

  /// Called when the avatar/name area is tapped. Typically navigates to
  /// the Profile screen.
  final VoidCallback? onAvatarTap;

  /// Called when the settings/gear icon is tapped.
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onAvatarTap,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  // TODO: Replace with the real user avatar asset once provided.
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.background,
                    child: Icon(
                      Icons.person,
                      color: AppColors.grayText,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textNavy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onSettingsTap,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.settings_outlined,
                color: AppColors.textNavy,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
