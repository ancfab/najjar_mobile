import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../theme/app_colors.dart';

/// Bordered "Live Specialist Support" card with a WhatsApp and an email
/// action button.
///
/// Both actions are exposed as callbacks rather than launching a URI
/// directly, so the Support screen can decide whether to open a real
/// WhatsApp/email link or show a "not yet available" message, depending on
/// whether verified contact details exist for the selected region.
class SupportActionCard extends StatelessWidget {
  const SupportActionCard({
    super.key,
    required this.onChatOnWhatsApp,
    required this.onEmailSupport,
  });

  final VoidCallback onChatOnWhatsApp;
  final VoidCallback onEmailSupport;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('supportAction.heading'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('supportAction.description'),
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.grayText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('support-whatsapp-button'),
              onPressed: onChatOnWhatsApp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.actionGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: Text(
                context.t('supportAction.chatWhatsapp'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('support-email-button'),
              onPressed: onEmailSupport,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textNavy,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.mail_outline_rounded, size: 18),
              label: Text(
                context.t('supportAction.emailSupport'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
