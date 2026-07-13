import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Full-width secondary red BACK button.
class SecondaryBackButton extends StatelessWidget {
  const SecondaryBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerRed,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: const Center(
              child: Text(
                'BACK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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
