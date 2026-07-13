import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A labeled text field matching the login form's field style
/// (light border, rounded corners, muted placeholder).
class LoginTextField extends StatelessWidget {
  const LoginTextField({
    super.key,
    required this.label,
    required this.hintText,
    this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.textInputAction,
  });

  final String label;
  final String hintText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;

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
            color: Color(0xFF1A1A1A),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            textInputAction: textInputAction,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(
                color: AppColors.grayText,
                fontSize: 15,
              ),
              filled: true,
              fillColor: AppColors.background,
              suffixIcon: suffixIcon,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primaryNavy),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
