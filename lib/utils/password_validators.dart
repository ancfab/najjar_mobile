import 'package:flutter/widgets.dart';

import '../localization/translations.dart';

/// Purpose: Local, synchronous password-strength/confirmation checks for
/// `ChangePasswordScreen`, run before any network call — mirrors the shape
/// of `contact_form_validators.dart` (a required-value check, then one or
/// more format checks, each returning the first failing localized
/// message).
///
/// Responsibilities:
/// - Enforce the documented new-password contract locally (≥8 characters,
///   mixed case, a number, a symbol) so an obviously-invalid password never
///   reaches the network.
/// - Confirm the confirmation field matches, locally, before submit.
///
/// Must not:
/// - Be treated as authoritative — the backend re-validates independently
///   and its response is still what ultimately decides success (see
///   `AuthService.changePassword`'s `weakPassword` mapping).

final RegExp _hasLowercase = RegExp(r'[a-z]');
final RegExp _hasUppercase = RegExp(r'[A-Z]');
final RegExp _hasDigit = RegExp(r'[0-9]');
final RegExp _hasSymbol = RegExp(r'[^a-zA-Z0-9]');

/// Validates the new-password field: required, at least 8 characters,
/// mixed case, at least one number, at least one symbol. Returns the first
/// failing rule's localized message, or `null` when every rule passes.
String? validateNewPassword(BuildContext context, String? value) {
  final password = value ?? '';
  if (password.isEmpty) {
    return context.t('changePassword.passwordRequired');
  }
  if (password.length < 8 ||
      !_hasLowercase.hasMatch(password) ||
      !_hasUppercase.hasMatch(password) ||
      !_hasDigit.hasMatch(password) ||
      !_hasSymbol.hasMatch(password)) {
    return context.t('changePassword.passwordRequirements');
  }
  return null;
}

/// Validates the confirm-password field against [newPassword]: required,
/// and must match exactly.
String? validatePasswordConfirmation(
  BuildContext context,
  String? value,
  String newPassword,
) {
  final confirmation = value ?? '';
  if (confirmation.isEmpty) {
    return context.t('changePassword.confirmPasswordRequired');
  }
  if (confirmation != newPassword) {
    return context.t('changePassword.passwordsDoNotMatch');
  }
  return null;
}
