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
        child: const SizedBox(
          height: 56,
          width: double.infinity,
          child: Center(
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
    );
  }
}
