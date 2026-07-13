import 'package:flutter/material.dart';

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
          const Text(
            'Live Specialist Support',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Instant connectivity with our textile specialists. Get '
            'real-time updates on fabric availability and logistics.',
            style: TextStyle(
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
              label: const Text(
                'CHAT ON WHATSAPP',
                style: TextStyle(
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
              label: const Text(
                'EMAIL SUPPORT',
                style: TextStyle(
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
