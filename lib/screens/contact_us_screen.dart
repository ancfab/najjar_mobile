import 'package:flutter/material.dart';

import '../data/support_regions_data.dart';
import '../models/contact_subject.dart';
import '../models/support_region.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/contact_form_field.dart';
import '../widgets/support_info_card.dart';

/// Contact Us form screen: reached from the Support landing screen's
/// "EMAIL SUPPORT" action. Collects a name, work email, subject, and
/// message, and shows the region-scoped Email/Office details already
/// modeled by [SupportRegionData].
///
/// TODO: No email-sending backend/API exists yet — see [_handleSubmit],
/// which currently only shows a placeholder SnackBar once the form
/// validates. Wire up the real Contact Us submission API there once it
/// exists.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key, this.region});

  /// The Support region selected on the landing screen, so this screen can
  /// show region-scoped contact details instead of generic/unrelated ones.
  /// Falls back to the first configured region when not supplied.
  final SupportRegionData? region;

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

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  ContactSubject? _selectedSubject;
  bool _isSubmitting = false;

  SupportRegionData get _region => widget.region ?? kSupportRegions.first;

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

  /// Validates the form and, once valid, shows a placeholder "not connected
  /// yet" SnackBar instead of pretending an email was sent.
  ///
  /// TODO: Replace this placeholder with a real submission call (e.g. to a
  /// Contact Us / email-support API) once that backend exists. The form
  /// data is available via [_fullNameController], [_workEmailController],
  /// [_selectedSubject], and [_messageController].
  void _handleSubmit() {
    if (_isSubmitting) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      _focusFirstInvalidField();
      return;
    }

    setState(() => _isSubmitting = true);
    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Email support submission is not connected yet.'),
        ),
      );

    // Guard only briefly against duplicate rapid taps; there is no real
    // network call to await yet.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
    });
  }

  void _focusFirstInvalidField() {
    if (_fullNameController.text.trim().isEmpty) {
      _fullNameFocusNode.requestFocus();
    } else if (_workEmailController.text.trim().isEmpty ||
        !_emailPattern.hasMatch(_workEmailController.text.trim())) {
      _workEmailFocusNode.requestFocus();
    } else if (_messageController.text.trim().isEmpty) {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBackToSupportLink(),
                    const SizedBox(height: 12),
                    _buildIntro(),
                    const SizedBox(height: 20),
                    _buildContactSummary(),
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
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textNavy),
            SizedBox(width: 6),
            Text(
              'Back to Support',
              style: TextStyle(
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
              const Text(
                'Contact Us',
                style: TextStyle(
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.support_agent_rounded,
                size: 14,
                color: AppColors.darkRedBrown,
              ),
              SizedBox(width: 6),
              Text(
                'SUPPORT CENTER',
                style: TextStyle(
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
        const Text(
          'Contact Us',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Connect with our textile experts to streamline your supply '
          'chain or inquire about our premium weave collections.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.grayText,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildContactSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SupportInfoCard(
          key: const ValueKey('contact-email-us-card'),
          icon: Icons.mail_outline_rounded,
          label: 'EMAIL US',
          child: Text(
            _region.supportEmail ?? 'Support email details will be added soon.',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textNavy,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SupportInfoCard(
          key: const ValueKey('contact-main-office-card'),
          icon: Icons.location_on_rounded,
          label: 'MAIN OFFICE',
          child: Text(
            _region.officeAddress ??
                'Office details for ${_region.displayName} will be added '
                    'soon.',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textNavy,
              height: 1.4,
            ),
          ),
        ),
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
            label: 'FULL NAME',
            child: TextFormField(
              key: const ValueKey('contact-full-name-field'),
              controller: _fullNameController,
              focusNode: _fullNameFocusNode,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
              decoration: _fieldDecoration(hintText: 'Jane Weaver'),
              onFieldSubmitted: (_) => _workEmailFocusNode.requestFocus(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your full name.';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          ContactFormField(
            label: 'WORK EMAIL',
            child: TextFormField(
              key: const ValueKey('contact-work-email-field'),
              controller: _workEmailController,
              focusNode: _workEmailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
              decoration: _fieldDecoration(hintText: 'jane@textile.co'),
              onFieldSubmitted: (_) => _messageFocusNode.requestFocus(),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return 'Please enter your work email.';
                }
                if (!_emailPattern.hasMatch(trimmed)) {
                  return 'Please enter a valid email address.';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          ContactFormField(
            label: 'SUBJECT',
            child: DropdownButtonFormField<ContactSubject>(
              key: const ValueKey('contact-subject-field'),
              initialValue: _selectedSubject,
              isExpanded: true,
              hint: const Text(
                'Select a subject',
                style: TextStyle(fontSize: 15, color: AppColors.grayText),
              ),
              style: const TextStyle(fontSize: 15, color: AppColors.textNavy),
              decoration: _fieldDecoration(),
              items: [
                for (final subject in ContactSubject.values)
                  DropdownMenuItem(
                    value: subject,
                    child: Text(subject.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (subject) {
                setState(() => _selectedSubject = subject);
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select a subject.';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          ContactFormField(
            label: 'MESSAGE BODY',
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
                hintText: 'Tell us more about your project requirements...',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a message.';
                }
                return null;
              },
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
        onTap: _isSubmitting ? null : _handleSubmit,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'SEND EMAIL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
