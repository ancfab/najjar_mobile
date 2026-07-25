import 'package:flutter/material.dart';

import '../data/country_codes.dart';
import '../models/auth/login_failure.dart';
import '../models/country_code.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/country_code_picker.dart';
import '../widgets/login/contact_us_link.dart';
import '../widgets/login/login_footer.dart';
import '../widgets/login/login_header.dart';
import '../widgets/login/login_text_field.dart';
import '../widgets/login/password_field.dart';
import '../widgets/login/primary_login_button.dart';
import '../widgets/login/secondary_back_button.dart';
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

  /// A safe, one-time message to show after a startup secure-session
  /// restore failure (see `main.dart`'s `resolveStartupSession`), or null
  /// when nothing needs to be shown.
  final String? startupMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileNumberController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  CountryCode _selectedCountry = kDefaultCountryCode;
  bool _isLoading = false;

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

    final message = widget.startupMessage;
    if (message != null) {
      // Shown once, after the first frame, using the screen's normal
      // SnackBar presentation — never during initState itself, since no
      // ScaffoldMessenger is reachable yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showMessage(message);
      });
    }
  }

  @override
  void dispose() {
    _mobileNumberController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    if (_ownsAuthService) _authService.close();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    final mobileNumber = _mobileNumberController.text.trim();
    final username = _usernameController.text;
    final password = _passwordController.text;

    if (_selectedCountry.isoCode.isEmpty ||
        mobileNumber.isEmpty ||
        username.trim().isEmpty ||
        password.isEmpty) {
      _showMessage('Please fill in all required fields.');
      return;
    }

    if (!_digitsOnly.hasMatch(mobileNumber)) {
      _showMessage('Mobile number should contain digits only.');
      return;
    }

    final phone = '${_selectedCountry.dialCode}$mobileNumber';

    setState(() => _isLoading = true);
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

    _showMessage(_messageFor(result as AuthLoginFailure));
  }

  /// Maps each [AuthLoginFailureType] to one neutral, safe message — never
  /// the backend's raw validation text, an HTTP status code, or any
  /// storage/transport implementation detail.
  String _messageFor(AuthLoginFailure failure) {
    switch (failure.type) {
      case AuthLoginFailureType.invalidInput:
        return 'Please fill in all required fields.';
      case AuthLoginFailureType.invalidCredentials:
        return 'Please check your login details and try again.';
      case AuthLoginFailureType.invalidPhone:
        return failure.phoneError ?? 'Please enter a valid mobile number.';
      case AuthLoginFailureType.network:
        return 'Unable to connect. Check your internet connection and '
            'try again.';
      case AuthLoginFailureType.serviceUnavailable:
        return 'The service is temporarily unavailable. Please try again.';
      case AuthLoginFailureType.invalidResponse:
        return 'We could not complete the login. Please try again.';
      case AuthLoginFailureType.secureStorage:
        return 'Login succeeded, but the session could not be saved '
            'securely. Please try again.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleContactUs() {
    // TODO: Navigate to the Contact Us screen once it exists.
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
                  const Text(
                    'MOBILE NUMBER',
                    style: TextStyle(
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
                        hintText: '50 123 4567',
                        hintStyle: const TextStyle(
                          color: AppColors.grayText,
                          fontSize: 15,
                        ),
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
                    label: 'CLIENT NAME',
                    hintText: 'Enter your name',
                    controller: _usernameController,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),
                  PasswordField(controller: _passwordController),
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
