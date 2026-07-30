import 'package:flutter/material.dart';

import '../../localization/translations.dart';
import '../../theme/app_colors.dart';

/// Tappable "Need help? Contact Us" link with a support icon.
class ContactUsLink extends StatelessWidget {
  const ContactUsLink({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  context.t('login.contactUsLink'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.support_agent_rounded,
                color: AppColors.textNavy,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
