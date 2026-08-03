import 'package:flutter/material.dart';

import '../../localization/translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Password field with a show/hide toggle. Masked by default.
class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('login.passwordLabel'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: TextField(
            controller: widget.controller,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: InputDecoration(
              hintText: context.t('login.passwordHint'),
              hintStyle: const TextStyle(
                color: AppColors.grayText,
                fontSize: 15,
              ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.grayText,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.inputAll,
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.inputAll,
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.inputAll,
                borderSide: const BorderSide(color: AppColors.primaryNavy),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
