import 'package:flutter/material.dart';

import '../data/country_codes.dart';
import '../localization/translations.dart';
import '../models/auth/login_failure.dart';
import '../models/country_code.dart';
import '../services/auth_service.dart';
import '../services/session_messages.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../utils/responsive.dart';
import '../widgets/country_code_picker.dart';
import '../widgets/login/contact_us_link.dart';
import '../widgets/login/login_footer.dart';
import '../widgets/login/login_header.dart';
import '../widgets/login/login_text_field.dart';
import '../widgets/login/password_field.dart';
import '../widgets/login/primary_login_button.dart';
import '../widgets/login/secondary_back_button.dart';
import 'contact_us_screen.dart';
import 'home_screen.dart';

/// Purpose: The Login screen's form state and presentation.
///
/// Responsibilities:
/// - Own the mobile number / username / password form fields and the
///   selected country, run inexpensive local validation, and call
///   [AuthService.login].
/// - Map the typed [AuthLoginResult] into a neutral, safe message or
///   navigation to Home.
///
/// Must not:
/// - Perform raw HTTP requests or secure-storage operations itself — both
///   already happen inside [AuthService]; a successful [AuthLoginSuccess]
///   means the session has already been persisted before this screen ever
///   sees the result.
/// - Log, display, or persist the password, token, or raw API/exception
///   detail.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authService, this.startupMessage});

  /// Login seam. Defaults (lazily, in State — see [_LoginScreenState]) to
  /// [AuthService.production]; overridable so tests can inject an
  /// [AuthService] wired to fakes instead of making a real network call or
  /// touching real secure storage.
  final AuthService? authService;

  /// A safe, one-time message reason to show after a startup secure-session
  /// restore failure (see `main.dart`'s `resolveStartupSession`), or null
  /// when nothing needs to be shown.
  final LoginStartupMessage? startupMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileNumberController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  CountryCode _selectedCountry = kDefaultCountryCode;
  bool _isLoading = false;

  // Local field-validation errors (missing/malformed input caught before
  // AuthService.login is ever called) — shown inline under each field,
  // never as a SnackBar or popup. Distinct from an API/login failure (see
  // _showLoginErrorDialog), which is a dialog. Each clears itself as soon
  // as the user edits the corresponding field again (see the controller
  // listeners added in initState).
  String? _mobileError;
  String? _usernameError;
  String? _passwordError;

  late final AuthService _authService;

  /// Whether this instance created [_authService] itself (via
  /// [AuthService.production]) as opposed to receiving a caller-injected
  /// one — only an owned service is closed by [dispose].
  late final bool _ownsAuthService;

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  @override
  void initState() {
    super.initState();
    final injected = widget.authService;
    if (injected != null) {
      _authService = injected;
      _ownsAuthService = false;
    } else {
      _authService = AuthService.production();
      _ownsAuthService = true;
    }

    // Clears each field's inline validation error as soon as the user
    // edits that field again, rather than leaving a stale error visible
    // until the next submit attempt.
    _mobileNumberController.addListener(_clearMobileError);
    _usernameController.addListener(_clearUsernameError);
    _passwordController.addListener(_clearPasswordError);

    final message = widget.startupMessage;
    if (message != null) {
      // Shown once, after the first frame, using the screen's normal
      // SnackBar presentation — never during initState itself, since no
      // ScaffoldMessenger is reachable yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showStartupMessage(_messageForStartupReason(message));
      });
    }
  }

  @override
  void dispose() {
    _mobileNumberController.removeListener(_clearMobileError);
    _usernameController.removeListener(_clearUsernameError);
    _passwordController.removeListener(_clearPasswordError);
    _mobileNumberController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    if (_ownsAuthService) _authService.close();
    super.dispose();
  }

  void _clearMobileError() {
    if (_mobileError != null) setState(() => _mobileError = null);
  }

  void _clearUsernameError() {
    if (_usernameError != null) setState(() => _usernameError = null);
  }

  void _clearPasswordError() {
    if (_passwordError != null) setState(() => _passwordError = null);
  }

  /// Local, pre-request validation for the mobile field: missing/empty
  /// input (bundled with the always-non-empty-in-practice country isoCode
  /// guard, since the country picker sits directly above this field) or
  /// non-digit characters. Returns null when valid.
  String? _validateMobile(String mobileNumber) {
    if (_selectedCountry.isoCode.isEmpty || mobileNumber.isEmpty) {
      return context.t('login.mobileNumberRequired');
    }
    if (!_digitsOnly.hasMatch(mobileNumber)) {
      return context.t('login.validationMobileDigitsOnly');
    }
    return null;
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    final mobileNumber = _mobileNumberController.text.trim();
    final username = _usernameController.text;
    final password = _passwordController.text;

    final mobileError = _validateMobile(mobileNumber);
    final usernameError = username.trim().isEmpty
        ? context.t('login.clientNameRequired')
        : null;
    final passwordError = password.isEmpty
        ? context.t('login.passwordRequired')
        : null;

    if (mobileError != null || usernameError != null || passwordError != null) {
      // Local field validation only — shown inline near each field, never
      // as a popup or SnackBar, and never sent to AuthService.login.
      setState(() {
        _mobileError = mobileError;
        _usernameError = usernameError;
        _passwordError = passwordError;
      });
      return;
    }

    final phone = '${_selectedCountry.dialCode}$mobileNumber';

    setState(() {
      _isLoading = true;
      _mobileError = null;
      _usernameError = null;
      _passwordError = null;
    });
    final AuthLoginResult result;
    try {
      result = await _authService.login(
        country: _selectedCountry.isoCode,
        phone: phone,
        username: username,
        password: password,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;

    _handleLoginResult(result);
  }

  void _handleLoginResult(AuthLoginResult result) {
    if (result is AuthLoginSuccess) {
      // The secure session is already persisted (see AuthService.login) —
      // navigating below is safe. Cleared as soon as practical now that
      // it's no longer needed, and before Home ever builds.
      _passwordController.clear();
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      return;
    }

    _showLoginErrorDialog(_messageFor(result as AuthLoginFailure));
  }

  /// Maps each [AuthLoginFailureType] to one neutral, safe message — never
  /// the backend's raw validation text, an HTTP status code, or any
  /// storage/transport implementation detail.
  String _messageFor(AuthLoginFailure failure) {
    switch (failure.type) {
      case AuthLoginFailureType.invalidInput:
        return context.t('login.failureRequiredFields');
      case AuthLoginFailureType.invalidCredentials:
        return context.t('login.failureInvalidCredentials');
      case AuthLoginFailureType.invalidPhone:
        return failure.phoneError ?? context.t('login.failureInvalidMobile');
      case AuthLoginFailureType.network:
        return context.t('login.failureNoConnection');
      case AuthLoginFailureType.serviceUnavailable:
        return context.t('login.failureServiceUnavailable');
      case AuthLoginFailureType.invalidResponse:
        return context.t('login.failureGeneric');
      case AuthLoginFailureType.secureStorage:
        return context.t('login.failureSessionNotSaved');
    }
  }

  /// Maps a [LoginStartupMessage] reason to one neutral, safe, localized
  /// message — mirroring [_messageFor]'s pattern for login failures.
  String _messageForStartupReason(LoginStartupMessage reason) {
    switch (reason) {
      case LoginStartupMessage.sessionExpired:
        return context.t('session.expired');
      case LoginStartupMessage.validationUnavailable:
        return context.t('session.validationUnavailable');
      case LoginStartupMessage.restoreFailed:
        return context.t('session.restoreFailed');
    }
  }

  /// Startup/session-message presentation only (e.g. session expired,
  /// restore failed) — the existing SnackBar style, shown once after this
  /// screen opens. Distinct from [_showLoginErrorDialog], which is used
  /// only for a failed login attempt.
  void _showStartupMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Login/API-failure presentation: a centered, dismissible popup — never
  /// a SnackBar. Dismisses the keyboard first so the dialog isn't shown
  /// behind it.
  Future<void> _showLoginErrorDialog(String message) {
    FocusScope.of(context).unfocus();
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('login-error-dialog'),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.dangerRed,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              context.t('login.errorDialogTitle'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            key: const ValueKey('login-error-dialog-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.t('common.ok')),
          ),
        ],
      ),
    );
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleContactUs() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ContactUsScreen()));
  }

  void _handlePrivacyPolicy() {
    // TODO: Navigate to the Privacy Policy screen once it exists.
  }

  void _handleTermsOfService() {
    // TODO: Navigate to the Terms of Service screen once it exists.
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ResponsiveMaxWidth(
            child: CenteredScrollable(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LoginHeader(),
                  const SizedBox(height: 28),
                  Text(
                    context.t('login.mobileNumberLabel'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CountryCodePicker(
                    selectedCountry: _selectedCountry,
                    onChanged: (country) {
                      setState(() => _selectedCountry = country);
                    },
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: TextField(
                      controller: _mobileNumberController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textNavy,
                      ),
                      decoration: InputDecoration(
                        hintText: context.t('login.mobileNumberHint'),
                        hintStyle: const TextStyle(
                          color: AppColors.grayText,
                          fontSize: 15,
                        ),
                        errorText: _mobileError,
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
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
                          borderSide: const BorderSide(
                            color: AppColors.primaryNavy,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  LoginTextField(
                    label: context.t('login.clientNameLabel'),
                    hintText: context.t('login.clientNameHint'),
                    controller: _usernameController,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    errorText: _usernameError,
                  ),
                  const SizedBox(height: 20),
                  PasswordField(
                    controller: _passwordController,
                    errorText: _passwordError,
                  ),
                  const SizedBox(height: 32),
                  PrimaryLoginButton(
                    onPressed: _handleLogin,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 14),
                  SecondaryBackButton(onPressed: _handleBack),
                  const SizedBox(height: 16),
                  ContactUsLink(onTap: _handleContactUs),
                  const Spacer(),
                  const SizedBox(height: 16),
                  LoginFooter(
                    onPrivacyPolicyTap: _handlePrivacyPolicy,
                    onTermsOfServiceTap: _handleTermsOfService,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
