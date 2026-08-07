import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../models/auth/change_password_result.dart';
import '../services/auth_service.dart';
import '../services/current_user_avatar_controller.dart';
import '../theme/app_colors.dart';
import '../utils/auth_result_navigation.dart';
import '../utils/password_validators.dart';
import '../utils/responsive.dart';
import '../widgets/login/password_field.dart';

/// Purpose: A dedicated screen for changing the authenticated user's
/// password against `PUT /api/auth/me/password`, reached from
/// `EditProfileScreen`'s "Change Password" action.
///
/// Responsibilities:
/// - Own the three password fields (current/new/confirm), run local
///   strength/confirmation validation before ever calling the network, and
///   call [AuthService.changePassword].
/// - Map the typed [ChangePasswordResult] into a neutral, safe message, a
///   distinct current-password error, or navigation to Login (on a
///   confirmed-expired session).
///
/// Must not:
/// - Crowd unrelated profile fields into this request — this screen only
///   ever submits the three password values, nothing else.
/// - Persist, cache, or log any of the three password values — they exist
///   only in their [TextEditingController]s for the lifetime of this
///   screen and are cleared immediately on success.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    this.authService,
    this.avatarController,
  });

  /// Change-password seam. Defaults (lazily, in State — see
  /// [_ChangePasswordScreenState]) to a real, owned [AuthService.production];
  /// overridable so tests (or a caller like `EditProfileScreen`, which
  /// already owns one) can supply an [AuthService] wired to fakes, or reuse
  /// an existing instance, instead of making a real network call.
  final AuthService? authService;

  /// Shared current-user avatar state, cleared on a confirmed-expired
  /// session the same way `EditProfileScreen`/`SessionExpiryCoordinator`
  /// already do. Defaults to the app-wide [currentUserAvatarController]
  /// singleton; overridable so tests can inject a fresh instance.
  final CurrentUserAvatarController? avatarController;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _newPasswordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _isSubmitting = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  // Backend-vetted field errors from the most recent attempt — cleared as
  // soon as the user edits any field again, the same convention
  // EditProfileScreen uses for its own server-driven field errors.
  String? _currentPasswordServerError;
  String? _newPasswordServerError;

  late final AuthService _authService;

  // Only set when this State created its own AuthService.production() (no
  // widget.authService was injected) — that instance is the only thing
  // this screen ever closes; a caller-injected AuthService (e.g.
  // EditProfileScreen's own, already-owned instance) is left alone.
  AuthService? _ownedAuthService;

  late final CurrentUserAvatarController _avatarController =
      widget.avatarController ?? currentUserAvatarController;

  @override
  void initState() {
    super.initState();
    final injected = widget.authService;
    if (injected != null) {
      _authService = injected;
    } else {
      final owned = AuthService.production();
      _ownedAuthService = owned;
      _authService = owned;
    }

    for (final controller in [
      _currentPasswordController,
      _newPasswordController,
      _confirmPasswordController,
    ]) {
      controller.addListener(_clearServerErrors);
    }
  }

  void _clearServerErrors() {
    if (_currentPasswordServerError == null &&
        _newPasswordServerError == null) {
      return;
    }
    setState(() {
      _currentPasswordServerError = null;
      _newPasswordServerError = null;
    });
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _ownedAuthService?.close();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _currentPasswordServerError = null;
      _newPasswordServerError = null;
    });
    FocusScope.of(context).unfocus();

    final ChangePasswordResult result;
    try {
      result = await _authService.changePassword(
        currentPassword: _currentPasswordController.text,
        password: _newPasswordController.text,
        passwordConfirmation: _confirmPasswordController.text,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
    if (!mounted) return;

    switch (result) {
      case ChangePasswordSuccess():
        // Never store or log a password value — clearing here is the only
        // place any of the three ever leave the controllers they were
        // typed into.
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() => _autovalidateMode = AutovalidateMode.disabled);
        _showSnackBar(context.t('changePassword.success'));
      case ChangePasswordFailure(type: ChangePasswordFailureType.unauthorized):
        handleUnauthorizedResult(context, _avatarController);
      case ChangePasswordFailure(
        type: ChangePasswordFailureType.incorrectCurrentPassword,
      ):
        setState(
          () => _currentPasswordServerError = context.t(
            'changePassword.incorrectCurrentPassword',
          ),
        );
      case ChangePasswordFailure(
        type: ChangePasswordFailureType.weakPassword ||
            ChangePasswordFailureType.passwordConfirmationMismatch,
        :final passwordError,
      ):
        setState(
          () => _newPasswordServerError =
              passwordError ?? context.t('changePassword.passwordRequirements'),
        );
      case ChangePasswordFailure():
        _showSnackBar(context.t('changePassword.failure'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              24,
              16,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ResponsiveMaxWidth(
              child: Form(
                key: _formKey,
                autovalidateMode: _autovalidateMode,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PasswordField(
                      key: const ValueKey('change-password-current-field'),
                      controller: _currentPasswordController,
                      label: context.t('changePassword.currentPasswordLabel'),
                      hint: context.t('changePassword.currentPasswordHint'),
                      textInputAction: TextInputAction.next,
                      errorText: _currentPasswordServerError,
                      onFieldSubmitted: (_) =>
                          _newPasswordFocusNode.requestFocus(),
                      validator: (value) => (value == null || value.isEmpty)
                          ? context.t('changePassword.currentPasswordRequired')
                          : null,
                    ),
                    const SizedBox(height: 20),
                    PasswordField(
                      key: const ValueKey('change-password-new-field'),
                      controller: _newPasswordController,
                      focusNode: _newPasswordFocusNode,
                      label: context.t('changePassword.newPasswordLabel'),
                      hint: context.t('changePassword.newPasswordHint'),
                      textInputAction: TextInputAction.next,
                      errorText: _newPasswordServerError,
                      onFieldSubmitted: (_) =>
                          _confirmPasswordFocusNode.requestFocus(),
                      validator: (value) => validateNewPassword(context, value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('changePassword.passwordRequirements'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.grayText,
                      ),
                    ),
                    const SizedBox(height: 20),
                    PasswordField(
                      key: const ValueKey('change-password-confirm-field'),
                      controller: _confirmPasswordController,
                      focusNode: _confirmPasswordFocusNode,
                      label: context.t('changePassword.confirmPasswordLabel'),
                      hint: context.t('changePassword.confirmPasswordHint'),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleSubmit(),
                      validator: (value) => validatePasswordConfirmation(
                        context,
                        value,
                        _newPasswordController.text,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textNavy,
      elevation: 0,
      toolbarHeight: 68,
      titleSpacing: 0,
      leading: IconButton(
        key: const ValueKey('change-password-back-button'),
        icon: Transform.flip(
          flipX: Directionality.of(context) == TextDirection.rtl,
          child: const Icon(Icons.arrow_back_rounded),
        ),
        tooltip: context.t('common.back'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        context.t('changePassword.title'),
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.textNavy,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: AppColors.border, height: 1),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Material(
      color: AppColors.primaryNavy,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('change-password-submit-button'),
        borderRadius: BorderRadius.circular(12),
        onTap: _isSubmitting ? null : _handleSubmit,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    context.t('changePassword.submit'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
