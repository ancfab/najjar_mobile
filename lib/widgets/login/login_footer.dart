import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Footer with copyright text and tappable Privacy Policy / Terms of Service
/// links.
class LoginFooter extends StatelessWidget {
  const LoginFooter({
    super.key,
    required this.onPrivacyPolicyTap,
    required this.onTermsOfServiceTap,
  });

  final VoidCallback onPrivacyPolicyTap;
  final VoidCallback onTermsOfServiceTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '© 2024 INDIGO LOOM TEXTILE PORTAL. ALL RIGHTS RESERVED.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            _FooterLink(text: 'Privacy Policy', onTap: onPrivacyPolicyTap),
            _FooterLink(text: 'Terms of Service', onTap: onTermsOfServiceTap),
          ],
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textNavy,
        ),
      ),
    );
  }
}
