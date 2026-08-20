import 'package:flutter/material.dart';

import '../data/support_regions_data.dart';
import '../localization/translations.dart';
import '../models/contact_subject.dart';
import '../models/support_region.dart';
import '../services/email_launcher.dart';
import '../services/phone_launcher.dart';
import '../theme/app_colors.dart';
import '../utils/contact_form_validators.dart';
import '../utils/responsive.dart';
import '../widgets/contact_form_field.dart';
import '../widgets/support_info_card.dart';
import '../widgets/support_region_selector.dart';
import '../widgets/support_regional_contact_tile.dart';

/// Contact Us screen: reached either from the Support landing screen's
/// "EMAIL SUPPORT" action (with a [region] already selected there) or
/// directly from Login (with no region yet). Shows region-scoped contact
/// details — email, office address, direct phone numbers, and (for Syria)
/// named regional representatives — sourced from [kSupportRegions], plus a
/// form whose Send action opens the device's email app addressed to the
/// selected region's verified support email.
///
/// [initialName]/[initialEmail] prefill the form once a real profile/session
/// source exists; both are null in production today (see
/// `lib/data/mock_user.dart` and the Login screen) and are only exercised by
/// tests.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({
    super.key,
    this.region,
    this.phoneLauncher = const PhoneLauncher(),
    this.emailLauncher = const EmailLauncher(),
    this.initialName,
    this.initialEmail,
  });

  /// The Support region selected on the landing screen. When null (e.g.
  /// opened directly from Login), this screen shows its own region selector
  /// instead of silently defaulting to one region behind the scenes.
  final SupportRegionData? region;

  /// Injectable so tests can supply a fake [UrlLauncherClient]-backed
  /// launcher instead of touching the real `url_launcher` plugin.
  final PhoneLauncher phoneLauncher;

  /// Injectable so tests can supply a fake [UrlLauncherClient]-backed
  /// launcher instead of touching the real `url_launcher` plugin.
  final EmailLauncher emailLauncher;

  /// Prefill values for the customer's name/email, sourced from a
  /// logged-in profile/session once one exists. Null in production today.
  final String? initialName;
  final String? initialEmail;

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _workEmailController = TextEditingController();
  final _messageController = TextEditingController();

  final _fullNameFocusNode = FocusNode();
  final _workEmailFocusNode = FocusNode();
  final _messageFocusNode = FocusNode();

  ContactSubject? _selectedSubject;
  bool _isSendingForm = false;
  bool _isEmailActionLaunching = false;
  bool _isPhoneLaunching = false;
  bool _nameEditedByUser = false;
  bool _emailEditedByUser = false;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  late SupportRegionId _selectedRegionId;

  bool get _showRegionSelector => widget.region == null;

  SupportRegionData get _region => kSupportRegions.firstWhere(
    (region) => region.id == _selectedRegionId,
    orElse: () => kSupportRegions.first,
  );

  @override
  void initState() {
    super.initState();
    _selectedRegionId = widget.region?.id ?? kSupportRegions.first.id;
    _applyProfilePrefill(widget.initialName, widget.initialEmail);
  }

  @override
  void didUpdateWidget(covariant ContactUsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.region != null && widget.region!.id != oldWidget.region?.id) {
      setState(() => _selectedRegionId = widget.region!.id);
    }
    if (widget.initialName != oldWidget.initialName ||
        widget.initialEmail != oldWidget.initialEmail) {
      _applyProfilePrefill(widget.initialName, widget.initialEmail);
    }
  }

  /// Prefills the name/email fields from a logged-in profile/session, once
  /// the customer hasn't touched and hasn't already typed something into,
  /// so late-arriving profile data can never clobber an in-progress edit.
  void _applyProfilePrefill(String? name, String? email) {
    final trimmedName = name?.trim() ?? '';
    if (!_nameEditedByUser &&
        trimmedName.isNotEmpty &&
        _fullNameController.text.isEmpty) {
      _fullNameController.text = trimmedName;
    }
    final trimmedEmail = email?.trim() ?? '';
    if (!_emailEditedByUser &&
        trimmedEmail.isNotEmpty &&
        _workEmailController.text.isEmpty) {
      _workEmailController.text = trimmedEmail;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _workEmailController.dispose();
    _messageController.dispose();
    _fullNameFocusNode.dispose();
    _workEmailFocusNode.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _handleBackToSupport() {
    Navigator.of(context).maybePop();
  }

  void _selectRegion(SupportRegionId regionId) {
    setState(() => _selectedRegionId = regionId);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onEmailUsTap() async {
    if (_isEmailActionLaunching) return;
    final email = _region.supportEmail;
    if (email == null) return;

    setState(() => _isEmailActionLaunching = true);
    try {
      final result = await widget.emailLauncher.send(to: email);
      if (!mounted) return;
      if (!result.succeeded) {
        _showSnackBar(context.t('contactUs.emailAppUnavailable'));
      }
    } finally {
      if (mounted) setState(() => _isEmailActionLaunching = false);
    }
  }

  Future<void> _onCallTap(String number) async {
    if (_isPhoneLaunching) return;

    setState(() => _isPhoneLaunching = true);
    try {
      final result = await widget.phoneLauncher.call(number);
      if (!mounted) return;
      if (!result.succeeded) {
        _showSnackBar(context.t('contactUs.dialerUnavailable'));
      }
    } finally {
      if (mounted) setState(() => _isPhoneLaunching = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (_isSendingForm) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      _focusFirstInvalidField();
      return;
    }

    final email = _region.supportEmail;
    if (email == null) {
      _showSnackBar(
        context.t(
          'contactUs.emailUnavailableForRegion',
          params: {'region': _region.displayName},
        ),
      );
      return;
    }

    final name = _fullNameController.text.trim();
    final workEmail = _workEmailController.text.trim();
    final message = _messageController.text.trim();
    final subjectLabel = _selectedSubject!.localizedLabel(context);
    final body = 'Name: $name\nEmail: $workEmail\n\n$message';

    setState(() => _isSendingForm = true);
    FocusScope.of(context).unfocus();

    try {
      final result = await widget.emailLauncher.send(
        to: email,
        subject: subjectLabel,
        body: body,
      );
      if (!mounted) return;
      if (!result.succeeded) {
        _showSnackBar(context.t('contactUs.sendEmailFailed'));
      }
    } finally {
      if (mounted) setState(() => _isSendingForm = false);
    }
  }

  void _focusFirstInvalidField() {
    if (validateRequiredField(_fullNameController.text, '') != null) {
      _fullNameFocusNode.requestFocus();
    } else if (validateEmailField(context, _workEmailController.text) != null) {
      _workEmailFocusNode.requestFocus();
    } else if (validateRequiredField(_messageController.text, '') != null) {
      _messageFocusNode.requestFocus();
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
              16,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ResponsiveMaxWidth(
              child: Form(
                key: _formKey,
                autovalidateMode: _autovalidateMode,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBackToSupportLink(),
                    const SizedBox(height: 12),
                    _buildIntro(),
                    const SizedBox(height: 20),
                    if (_showRegionSelector) ...[
                      _buildRegionSelector(),
                      const SizedBox(height: 20),
                    ],
                    _buildContactSummary(),
                    if (_region.regionalContacts.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildRegionalContacts(),
                    ],
                    const SizedBox(height: 20),
                    _buildFormCard(),
                    const SizedBox(height: 24),
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
      titleSpacing: 16,
      title: ClampedTextScale(child: _buildHeaderTitle()),
    );
  }

  // "Back to Support" breadcrumb-style link, matching the tappable-text
  // back-navigation pattern used by the Order Detail screen's breadcrumb.
  // Kept in the scrollable body (rather than the AppBar) so it never
  // competes with the brand mark for toolbar width on narrow screens.
  Widget _buildBackToSupportLink() {
    return InkWell(
      key: const ValueKey('contact-back-to-support-button'),
      onTap: _handleBackToSupport,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.flip(
              flipX: Directionality.of(context) == TextDirection.rtl,
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: AppColors.textNavy,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              context.t('contactUs.backToSupport'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Small brand mark + "Indigo Loom" eyebrow + page title, matching the
  // header style used by the Support screen.
  Widget _buildHeaderTitle() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryNavy,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text(
            'IL',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Indigo Loom',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: AppColors.grayText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                context.t('contactUs.title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textNavy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('contact-support-center-tag'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.peach.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.support_agent_rounded,
                size: 14,
                color: AppColors.darkRedBrown,
              ),
              const SizedBox(width: 6),
              Text(
                context.t('contactUs.tag'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.darkRedBrown,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.t('contactUs.title'),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.t('contactUs.intro'),
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.grayText,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildRegionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('contactUs.selectRegionLabel'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.grayText,
          ),
        ),
        const SizedBox(height: 10),
        SupportRegionSelector(
          key: const ValueKey('contact-region-selector'),
          regions: kSupportRegions,
          selectedRegionId: _selectedRegionId,
          onRegionSelected: _selectRegion,
        ),
      ],
    );
  }

  Widget _buildContactSummary() {
    final email = _region.supportEmail;
    final office = _region.officeAddress;
    final hotlineNumbers = _region.hotlineNumbers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (email != null) ...[
          SupportInfoCard(
            key: const ValueKey('contact-email-us-card'),
            icon: Icons.mail_outline_rounded,
            label: context.t('contactUs.emailUsLabel'),
            child: Semantics(
              button: true,
              label: context.t(
                'contactUs.emailAction',
                params: {'email': email},
              ),
              child: InkWell(
                key: const ValueKey('contact-email-us-action'),
                onTap: _onEmailUsTap,
                borderRadius: BorderRadius.circular(8),
                child: Text(
                  email,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryNavy,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (office != null) ...[
          SupportInfoCard(
            key: const ValueKey('contact-main-office-card'),
            icon: Icons.location_on_rounded,
            label: context.t('contactUs.mainOfficeLabel'),
            child: Text(
              office,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textNavy,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (hotlineNumbers.isNotEmpty)
          SupportInfoCard(
            key: const ValueKey('contact-call-us-card'),
            icon: Icons.call_rounded,
            label: context.t('contactUs.callUsLabel'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final number in hotlineNumbers)
                  Semantics(
                    button: true,
                    label: context.t(
                      'contactUs.callNumber',
                      params: {'number': number},
                    ),
                    child: InkWell(
                      key: ValueKey('contact-hotline-number-$number'),
                      onTap: () => _onCallTap(number),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          number,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRegionalContacts() {
    final upholstery = _region.regionalContacts
        .where((c) => c.category == SupportContactCategory.upholsteryFabrics)
        .toList();
    final curtains = _region.regionalContacts
        .where((c) => c.category == SupportContactCategory.curtains)
        .toList();

    return Container(
      key: const ValueKey('contact-regional-contacts-section'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('contactUs.regionalContactsLabel'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.grayText,
            ),
          ),
          if (upholstery.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildRegionalContactGroup(
              context.t('contactUs.upholsteryFabricsLabel'),
              upholstery,
            ),
          ],
          if (curtains.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildRegionalContactGroup(
              context.t('contactUs.curtainsLabel'),
              curtains,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRegionalContactGroup(
    String groupLabel,
    List<SupportRegionalContact> contacts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          groupLabel,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
          ),
        ),
        const SizedBox(height: 8),
        for (final contact in contacts) ...[
          SupportRegionalContactTile(
            key: ValueKey(
              'regional-contact-${contact.category.name}-'
              '${contact.name}-${contact.area}',
            ),
            contact: contact,
            onCallTap: _onCallTap,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContactFormField(
            label: context.t('contactUs.fullNameLabel'),
            child: TextFormField(
              key: const ValueKey('contact-full-name-field'),
              controller: _fullNameController,
              focusNode: _fullNameFocusNode,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
              decoration: _fieldDecoration(
                hintText: context.t('contactUs.fullNameHint'),
              ),
              onFieldSubmitted: (_) => _workEmailFocusNode.requestFocus(),
              onChanged: (_) => _nameEditedByUser = true,
              validator: (value) => validateRequiredField(
                value,
                context.t('contactUs.fullNameError'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ContactFormField(
            label: context.t('contactUs.workEmailLabel'),
            child: TextFormField(
              key: const ValueKey('contact-work-email-field'),
              controller: _workEmailController,
              focusNode: _workEmailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
              decoration: _fieldDecoration(
                hintText: context.t('contactUs.workEmailHint'),
              ),
              onFieldSubmitted: (_) => _messageFocusNode.requestFocus(),
              onChanged: (_) => _emailEditedByUser = true,
              validator: (value) => validateEmailField(context, value),
            ),
          ),
          const SizedBox(height: 20),
          ContactFormField(
            label: context.t('contactUs.subjectLabel'),
            child: DropdownButtonFormField<ContactSubject>(
              key: const ValueKey('contact-subject-field'),
              initialValue: _selectedSubject,
              isExpanded: true,
              hint: Text(
                context.t('contactUs.selectSubjectHint'),
                style: const TextStyle(fontSize: 15, color: AppColors.grayText),
              ),
              style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
              decoration: _fieldDecoration(),
              items: [
                for (final subject in ContactSubject.values)
                  DropdownMenuItem(
                    value: subject,
                    child: Text(
                      subject.localizedLabel(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (subject) {
                setState(() => _selectedSubject = subject);
              },
              validator: (value) => validateSubjectField(context, value),
            ),
          ),
          const SizedBox(height: 20),
          ContactFormField(
            label: context.t('contactUs.messageLabel'),
            child: TextFormField(
              key: const ValueKey('contact-message-field'),
              controller: _messageController,
              focusNode: _messageFocusNode,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
              decoration: _fieldDecoration(
                hintText: context.t('contactUs.messageHint'),
              ),
              validator: (value) => validateRequiredField(
                value,
                context.t('contactUs.messageError'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSendButton(),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: AppColors.grayText, fontSize: 15),
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

  Widget _buildSendButton() {
    return Material(
      color: AppColors.primaryNavy,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('contact-send-email-button'),
        borderRadius: BorderRadius.circular(12),
        onTap: _isSendingForm ? null : _handleSubmit,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: _isSendingForm
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          context.t('contactUs.sendButton'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
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
