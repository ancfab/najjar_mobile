import 'package:flutter/material.dart';

import '../data/mock_profile_data.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/contact_form_validators.dart';
import '../utils/responsive.dart';
import '../widgets/contact_form_field.dart';
import '../widgets/custom_bottom_nav.dart';
import 'orders_screen.dart';
import 'support_screen.dart';

// Bottom tab bar indexes, matching HomeScreen's. This screen is itself the
// Profile tab's destination, so Profile is kept as the selected tab.
const int _navIndexHome = 0;
const int _navIndexOrders = 1;
const int _navIndexSupport = 2;
const int _navIndexProfile = 3;

/// Edit Profile screen: avatar with a camera/edit overlay, client info
/// (ANC ID + last-updated label), a prefilled editable form, a compact
/// "Save Changes" action, and a full-width "Logout" action.
///
/// TODO(api): Replace mock profile display/prefill data (see
/// [kMockUserProfile]) once the profile API/backend contract is confirmed.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    this.profile = kMockUserProfile,
    ProfileService? service,
  }) : service = service ?? const UnavailableProfileService();

  /// Display/prefill data for the avatar section and form fields. Defaults
  /// to the isolated mock profile; overridable so tests can inject fixed
  /// values.
  final UserProfile profile;

  /// Save-changes seam. Defaults to the explicitly non-production
  /// [UnavailableProfileService]; overridable so tests can inject a fake.
  final ProfileService service;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _fullNameController = TextEditingController(
    text: widget.profile.fullName,
  );
  late final _emailController = TextEditingController(
    text: widget.profile.email,
  );
  late final _phoneController = TextEditingController(
    text: widget.profile.phone,
  );
  late final _companyController = TextEditingController(
    text: widget.profile.company,
  );
  late final _businessAddressController = TextEditingController(
    text: widget.profile.businessAddress,
  );

  final _emailFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _companyFocusNode = FocusNode();
  final _businessAddressFocusNode = FocusNode();

  // Normalized snapshot of the profile as loaded, kept separately from
  // [widget.profile] so dirty-state comparison survives widget rebuilds
  // without re-reading (and re-trimming) the source profile each time.
  // Mutable (not `late final`): a successful save moves this snapshot
  // forward to the just-submitted values, so the form is clean again
  // afterwards instead of permanently reporting unsaved changes.
  late String _initialFullName;
  late String _initialEmail;
  late String _initialPhone;
  late String _initialCompany;
  late String _initialBusinessAddress;

  bool _isSaving = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  List<TextEditingController> get _formControllers => [
    _fullNameController,
    _emailController,
    _phoneController,
    _companyController,
    _businessAddressController,
  ];

  // Trimmed current values compared against the initial snapshot, so Save
  // Changes stays disabled until the form actually differs from the
  // loaded profile (whitespace-only edits don't count as a change).
  bool get _isDirty {
    return _fullNameController.text.trim() != _initialFullName ||
        _emailController.text.trim() != _initialEmail ||
        _phoneController.text.trim() != _initialPhone ||
        _companyController.text.trim() != _initialCompany ||
        _businessAddressController.text.trim() != _initialBusinessAddress;
  }

  @override
  void initState() {
    super.initState();
    _initialFullName = widget.profile.fullName.trim();
    _initialEmail = widget.profile.email.trim();
    _initialPhone = widget.profile.phone.trim();
    _initialCompany = widget.profile.company.trim();
    _initialBusinessAddress = widget.profile.businessAddress.trim();
    for (final controller in _formControllers) {
      controller.addListener(_handleFormChanged);
    }
  }

  // Rebuilds so the Save Changes button's enabled state tracks [_isDirty]
  // as the user types.
  void _handleFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _formControllers) {
      controller.removeListener(_handleFormChanged);
    }
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _businessAddressController.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _companyFocusNode.dispose();
    _businessAddressFocusNode.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Camera overlay tap handler.
  //
  // TODO(api): Connect profile image selection/upload after the profile
  // media contract is available.
  void _handleChangePhoto() {
    _showSnackBar('Profile photo upload is not available yet.');
  }

  Future<void> _handleSave() async {
    if (_isSaving || !_isDirty) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }

    final request = ProfileUpdateRequest(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      company: _companyController.text.trim(),
      businessAddress: _businessAddressController.text.trim(),
    );

    setState(() => _isSaving = true);
    FocusScope.of(context).unfocus();

    try {
      final result = await widget.service.updateProfile(request);
      if (!mounted) return;
      switch (result.outcome) {
        case ProfileUpdateOutcome.success:
          // Moves the dirty-state baseline forward to what was just saved,
          // so the form reads as clean again instead of still reporting
          // (and warning on back navigation about) changes already saved.
          _initialFullName = request.fullName;
          _initialEmail = request.email;
          _initialPhone = request.phone;
          _initialCompany = request.company;
          _initialBusinessAddress = request.businessAddress;
          _showSnackBar(result.message ?? 'Profile updated.');
        case ProfileUpdateOutcome.failure:
          _showSnackBar(
            result.message ??
                "We couldn't save your changes. Please try again.",
          );
        case ProfileUpdateOutcome.unavailable:
          _showSnackBar('Profile updates are not connected yet.');
      }
    } catch (error) {
      // Technical detail only — never the submitted profile fields.
      debugPrint('Profile update failed: $error');
      if (!mounted) return;
      _showSnackBar("We couldn't save your changes. Please try again.");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Logout button tap handler.
  //
  // TODO(api): Connect logout to the confirmed authentication/session-
  // clearing flow.
  void _handleLogout() {
    _showSnackBar('Logout is not connected yet.');
  }

  // Called whenever something (the back button, a system back gesture, or
  // the bottom nav's Home tab, all of which go through `maybePop`) tries to
  // leave this screen while [_isDirty] blocked it via [PopScope.canPop].
  // Confirms the user actually wants to discard unsaved changes before
  // completing the pop; `Navigator.pop` (not `maybePop`) is used here since
  // it leaves unconditionally rather than being blocked again by the same
  // `canPop` check.
  Future<void> _handleAttemptedPop(bool didPop, Object? result) async {
    if (didPop) return;
    final shouldDiscard = await _confirmDiscardChanges();
    if (shouldDiscard && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('edit-profile-discard-dialog'),
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes to your profile. If you leave now, '
          'these changes will be lost.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('edit-profile-discard-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            key: const ValueKey('edit-profile-discard-confirm'),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return shouldDiscard ?? false;
  }

  // Handles bottom tab bar taps. Home returns to the screen this was
  // pushed from; Orders/Support push their screens the same way the rest
  // of the app's bottom nav does. Profile is a no-op: this screen already
  // is the Profile tab's destination, so selecting it again must not push
  // a duplicate instance.
  void _handleBottomNavTap(int tabIndex) {
    switch (tabIndex) {
      case _navIndexHome:
        Navigator.of(context).maybePop();
        break;
      case _navIndexOrders:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
        break;
      case _navIndexSupport:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SupportScreen()));
        break;
      case _navIndexProfile:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Blocks a "soft" pop (back button/gesture, or the bottom nav's Home
      // tab — all routed through `maybePop`) while there are unsaved
      // edits, so [_handleAttemptedPop] can confirm before discarding them.
      canPop: !_isDirty,
      onPopInvokedWithResult: _handleAttemptedPop,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(child: _buildFormBody()),
                CustomBottomNav(
                  currentIndex: _navIndexProfile,
                  onTap: _handleBottomNavTap,
                ),
              ],
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
        key: const ValueKey('edit-profile-back-button'),
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const ClampedTextScale(
        child: Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
          ),
        ),
      ),
      // Visual-only, matching the reference layout. No menu actions are
      // defined for this icon yet, so it's non-interactive rather than
      // wired to invented behavior.
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.more_vert_rounded, color: AppColors.textNavy),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: AppColors.border, height: 1),
      ),
    );
  }

  Widget _buildFormBody() {
    return SingleChildScrollView(
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
              _buildAvatarSection(),
              const SizedBox(height: 28),
              _buildFormFields(),
              const SizedBox(height: 24),
              _buildSaveButton(),
              const SizedBox(height: 32),
              _buildLogoutButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final profile = widget.profile;
    return Center(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                key: const ValueKey('edit-profile-avatar'),
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryNavy, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: const Icon(
                  Icons.person,
                  size: 56,
                  color: AppColors.grayText,
                ),
              ),
              Positioned(
                right: -6,
                bottom: -6,
                child: GestureDetector(
                  key: const ValueKey('edit-profile-camera-button'),
                  onTap: _handleChangePhoto,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primaryNavy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'ANC ID: #${profile.ancId}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.profileUpdatedLabel,
            style: const TextStyle(fontSize: 13, color: AppColors.grayText),
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContactFormField(
          label: 'Full Name',
          child: TextFormField(
            key: const ValueKey('edit-profile-full-name-field'),
            controller: _fullNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            onFieldSubmitted: (_) => _emailFocusNode.requestFocus(),
            validator: (value) =>
                validateRequiredField(value, 'Please enter your full name.'),
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: 'Email Address',
          child: TextFormField(
            key: const ValueKey('edit-profile-email-field'),
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            onFieldSubmitted: (_) => _phoneFocusNode.requestFocus(),
            validator: validateEmailField,
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: 'Phone Number',
          child: TextFormField(
            key: const ValueKey('edit-profile-phone-field'),
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            onFieldSubmitted: (_) => _companyFocusNode.requestFocus(),
            validator: validatePhoneField,
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: 'Company',
          child: TextFormField(
            key: const ValueKey('edit-profile-company-field'),
            controller: _companyController,
            focusNode: _companyFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            onFieldSubmitted: (_) => _businessAddressFocusNode.requestFocus(),
            validator: (value) =>
                validateRequiredField(value, 'Please enter your company.'),
          ),
        ),
        const SizedBox(height: 20),
        ContactFormField(
          label: 'Business Address',
          child: TextFormField(
            key: const ValueKey('edit-profile-business-address-field'),
            controller: _businessAddressController,
            focusNode: _businessAddressFocusNode,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.done,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
            decoration: _fieldDecoration(),
            validator: (value) => validateRequiredField(
              value,
              'Please enter your business address.',
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.dangerRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.dangerRed, width: 1.5),
      ),
    );
  }

  // Compact, centered "Save Changes" action, matching the reference's
  // intrinsic-width button rather than the app's usual full-width buttons.
  Widget _buildSaveButton() {
    return Center(
      child: Material(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('edit-profile-save-button'),
          borderRadius: BorderRadius.circular(12),
          onTap: _isSaving || !_isDirty ? null : _handleSave,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            child: Center(
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Material(
      color: AppColors.dangerRed,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('edit-profile-logout-button'),
        borderRadius: BorderRadius.circular(12),
        onTap: _handleLogout,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: const Center(
              child: Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
