import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// Minimal placeholder Profile screen.
///
/// TODO: Replace with the real profile UI (contact details, addresses,
/// account actions, etc.) once the backend/API for user profiles is defined.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: CenteredScrollable(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.background,
                  child: Icon(
                    Icons.person,
                    color: AppColors.grayText,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  userName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textNavy,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Profile details coming soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.grayText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
