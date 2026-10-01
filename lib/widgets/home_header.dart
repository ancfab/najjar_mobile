import 'package:flutter/material.dart';

import '../services/current_user_avatar_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'language_popup_menu.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.userName,
    this.onAvatarTap,
    this.avatarController,
  });

  final String userName;

  /// Called when the avatar/name area is tapped. Typically navigates to
  /// the Profile screen.
  final VoidCallback? onAvatarTap;

  /// Shared current-user avatar state. Defaults to the app-wide
  /// [currentUserAvatarController] singleton; overridable so tests can
  /// inject a fresh instance instead of sharing that mutable singleton
  /// across test cases.
  final CurrentUserAvatarController? avatarController;

  /// Gap between the logo and the language button in the right-side action
  /// group.
  static const double _actionGroupGap = 12;

  /// Logo height. Larger than it was beside the old settings gear: with
  /// that button gone the brand mark is the header's right-hand anchor, and
  /// it still clears the header's existing minHeight of 68.
  static const double _logoHeight = 44;

  @override
  Widget build(BuildContext context) {
    final controller = avatarController ?? currentUserAvatarController;
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
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
                      style: AppTypography.pageTitle.copyWith(
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: const ValueKey('home-header-logo'),
                height: _logoHeight,
                child: Image.asset(
                  'assets/logo/ANC Logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: _actionGroupGap),
              LanguagePopupMenuButton(
                key: const ValueKey('home-header-language-button'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
