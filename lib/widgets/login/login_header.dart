import 'package:flutter/material.dart';

import '../../localization/translations.dart';
import '../../theme/app_colors.dart';

class LoginHeader extends StatelessWidget {
  const LoginHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      context.t('login.welcomeBack'),
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        color: AppColors.textNavy,
      ),
    );
  }
}
