import 'package:flutter/material.dart';

import '../../localization/translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';

/// Full-width secondary red BACK button.
class SecondaryBackButton extends StatelessWidget {
  const SecondaryBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerRed,
      borderRadius: AppRadius.buttonAll,
      child: InkWell(
        borderRadius: AppRadius.buttonAll,
        onTap: onPressed,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: Text(
                context.t('login.backButton'),
                style: AppTypography.buttonText.copyWith(
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
