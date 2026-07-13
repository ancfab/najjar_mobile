import 'package:flutter/material.dart';

import '../data/country_codes.dart';
import '../models/country_code.dart';
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileNumberController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _passwordController = TextEditingController();

  CountryCode _selectedCountry = kDefaultCountryCode;
  bool _isLoading = false;

  @override
  void dispose() {
    _mobileNumberController.dispose();
    _clientNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  Future<void> _handleLogin() async {
    final mobileNumber = _mobileNumberController.text.trim();
    final password = _passwordController.text;

    if (_selectedCountry.dialCode.isEmpty ||
        mobileNumber.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields.')),
      );
      return;
    }

    if (!_digitsOnly.hasMatch(mobileNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mobile number should contain digits only.'),
        ),
      );
      return;
    }

    final fullPhoneNumber = '${_selectedCountry.dialCode}$mobileNumber';

    setState(() => _isLoading = true);
    // TODO: Wire up the real authentication API call using
    // fullPhoneNumber, _clientNameController.text, and password. Currently
    // any non-empty input is treated as a successful login so the Home
    // screen is reachable for frontend development; navigation below
    // should move behind the real API's success response once it exists.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isLoading = false);

    debugPrint('Login attempted for $fullPhoneNumber');

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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
                    controller: _clientNameController,
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
