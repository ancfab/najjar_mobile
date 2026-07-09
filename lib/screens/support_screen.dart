import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Minimal placeholder Support screen.
///
/// TODO: Replace with the real support experience (FAQs, contact options,
/// ticket history, etc.) once support content/backend is defined.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        title: const Text('Support'),
      ),
      body: const Center(
        child: Text(
          'Support content coming soon',
          style: TextStyle(color: AppColors.grayText),
        ),
      ),
    );
  }
}
