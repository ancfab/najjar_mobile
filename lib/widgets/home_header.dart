import 'package:flutter/material.dart';

import '../services/current_user_avatar_controller.dart';
import '../theme/app_colors.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.userName,
    this.onAvatarTap,
    this.onSettingsTap,
    this.avatarController,
  });

  final String userName;

  /// Called when the avatar/name area is tapped. Typically navigates to
  /// the Profile screen.
  final VoidCallback? onAvatarTap;

  /// Called when the settings/gear icon is tapped.
  final VoidCallback? onSettingsTap;

  /// Shared current-user avatar state. Defaults to the app-wide
  /// [currentUserAvatarController] singleton; overridable so tests can
  /// inject a fresh instance instead of sharing that mutable singleton
  /// across test cases.
  final CurrentUserAvatarController? avatarController;

  @override
  Widget build(BuildContext context) {
    final controller = avatarController ?? currentUserAvatarController;
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
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
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final image = controller.imageProvider;
                      return CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.background,
                        backgroundImage: image,
                        child: image == null
                            ? const Icon(
                                Icons.person,
                                color: AppColors.grayText,
                                size: 20,
                              )
                            : null,
                      );
                    },
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
