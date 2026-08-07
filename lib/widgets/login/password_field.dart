import 'package:flutter/material.dart';

import '../../localization/translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Password field with a show/hide toggle. Masked by default.
///
/// [label]/[hint] default to the Login screen's exact original copy so
/// existing call sites (and their tests) are unaffected; a caller with a
/// different field (e.g. "Current Password" on `ChangePasswordScreen`)
/// overrides both. [validator]/[errorText] are optional — omitted, this
/// behaves exactly as it always has (a plain masked `TextField` with no
/// validation of its own).
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.focusNode,
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
    this.validator,
    this.errorText,
  });

  final TextEditingController controller;

  /// Field label, shown above the input. Defaults to
  /// `context.t('login.passwordLabel')`.
  final String? label;

  /// Placeholder text. Defaults to `context.t('login.passwordHint')`.
  final String? hint;

  final FocusNode? focusNode;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  /// Local synchronous validation, run the same way any other
  /// [TextFormField.validator] is (on submit, or continuously once
  /// `AutovalidateMode.onUserInteraction` is active). Omitted for
  /// [PasswordField]'s original login-screen usage, which has no inline
  /// validation.
  final FormFieldValidator<String>? validator;

  /// A backend-vetted field error to show even before [validator] would
  /// otherwise re-run (e.g. "incorrect current password") — the same
  /// externally-driven-error pattern used elsewhere in this app (see
  /// `EditProfileScreen._fieldDecoration`).
  final String? errorText;

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
          widget.label ?? context.t('login.passwordLabel'),
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
          child: TextFormField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            obscureText: _obscure,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onFieldSubmitted,
            validator: widget.validator,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: InputDecoration(
              hintText: widget.hint ?? context.t('login.passwordHint'),
              hintStyle: const TextStyle(
                color: AppColors.grayText,
                fontSize: 15,
              ),
              errorText: widget.errorText,
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
