import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small uppercase field label above [child], matching the login form's
/// field-label style. Used by the Contact Us form so every field (text
/// input, dropdown, or text area) shares the same label treatment without
/// repeating the label `Text` style at each call site.
class ContactFormField extends StatelessWidget {
  const ContactFormField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.grayText,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
