import 'package:flutter/material.dart';

import '../data/support_regions_data.dart';
import '../models/support_region.dart';
import '../services/whatsapp_launcher.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/support_action_card.dart';
import '../widgets/support_hours_card.dart';
import '../widgets/support_info_card.dart';
import '../widgets/support_region_selector.dart';
import '../widgets/support_textile_visual.dart';
import 'contact_us_screen.dart';

/// Support landing screen: intro copy, a region selector, and region-scoped
/// contact cards (live chat/email, corporate office, direct hotline, and
/// support hours).
///
/// TODO: Contact details (email, office address, hotline numbers, support
/// hours) are not yet verified for any region — see
/// `lib/data/support_regions_data.dart` for where to plug in confirmed
/// values, and this screen's `_onCallHotline` for where to wire up a real
/// `url_launcher` call once hotline behavior is defined. WhatsApp is
/// already wired to `WhatsAppLauncher`, but still shows a "not yet
/// available" message per region until `whatsappNumber` is populated.
class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    WhatsAppLauncher? whatsAppLauncher,
    List<SupportRegionData>? regions,
  }) : whatsAppLauncher = whatsAppLauncher ?? const WhatsAppLauncher(),
       regions = regions ?? kSupportRegions;

  /// Injectable so tests can supply a fake launcher instead of touching the
  /// real `url_launcher` plugin.
  final WhatsAppLauncher whatsAppLauncher;

  /// Injectable so tests can exercise the "WhatsApp number available"
  /// launch flow with a test-only region, since no production region in
  /// `kSupportRegions` has a verified `whatsappNumber` yet. Defaults to
  /// `kSupportRegions`.
  final List<SupportRegionData> regions;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late SupportRegionId _selectedRegionId = widget.regions.first.id;
  bool _isWhatsAppLaunching = false;

  SupportRegionData get _selectedRegion =>
      widget.regions.firstWhere((region) => region.id == _selectedRegionId);

  void _selectRegion(SupportRegionId regionId) {
    setState(() => _selectedRegionId = regionId);
  }

  Future<void> _onChatOnWhatsApp() async {
    if (_isWhatsAppLaunching) return;

    // Read the region fresh at tap time (not captured earlier) so a region
    // switch before this async work resolves can't use stale contact data.
    final region = _selectedRegion;
    final number = region.whatsappNumber;
    if (number == null || number.trim().isEmpty) {
      _showSnackBar(
        'WhatsApp support is not available for ${region.displayName} yet.',
      );
      return;
    }

    setState(() => _isWhatsAppLaunching = true);
    try {
      final result = await widget.whatsAppLauncher.open(number);
      if (!mounted) return;
      if (!result.succeeded) {
        _showSnackBar(
          "Couldn't open WhatsApp for ${region.displayName}. Please try "
          'again later.',
        );
      }
    } finally {
      if (mounted) setState(() => _isWhatsAppLaunching = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onEmailSupport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactUsScreen(region: _selectedRegion),
      ),
    );
  }

  void _onCallHotline(String number) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calling $number is not yet available.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textNavy,
        elevation: 0,
        toolbarHeight: 68,
        titleSpacing: 16,
        title: ClampedTextScale(child: _buildHeaderTitle()),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ResponsiveMaxWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildIntro(),
                const SizedBox(height: 20),
                SupportRegionSelector(
                  key: const ValueKey('support-region-selector'),
                  regions: widget.regions,
                  selectedRegionId: _selectedRegionId,
                  onRegionSelected: _selectRegion,
                ),
                const SizedBox(height: 20),
                SupportActionCard(
                  onChatOnWhatsApp: _onChatOnWhatsApp,
                  onEmailSupport: _onEmailSupport,
                ),
                const SizedBox(height: 20),
                const SupportTextileVisual(),
                const SizedBox(height: 20),
                SupportInfoCard(
                  key: const ValueKey('support-corporate-office-card'),
                  icon: Icons.apartment_rounded,
                  label: 'CORPORATE OFFICE',
                  child: Text(
                    _selectedRegion.officeAddress ??
                        'Office details for ${_selectedRegion.displayName} '
                            'will be added soon.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textNavy,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SupportInfoCard(
                  key: const ValueKey('support-hotline-card'),
                  icon: Icons.call_rounded,
                  label: 'DIRECT HOTLINE',
                  child: _buildHotlineContent(),
                ),
                const SizedBox(height: 16),
                SupportHoursCard(
                  key: const ValueKey('support-hours-card'),
                  scheduleText:
                      _selectedRegion.supportHours ??
                      'Support hours for ${_selectedRegion.displayName} '
                          'will be confirmed soon.',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // App bar title: small brand mark + "Indigo Loom" eyebrow + page title,
  // matching the header style used by the Orders screen.
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
                'Support',
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
          key: const ValueKey('support-center-tag'),
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
          'How can we help your business thrive?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Our textile specialists and supply chain experts are available '
          '24/7 to ensure your production remains seamless.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.grayText,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildHotlineContent() {
    final numbers = _selectedRegion.hotlineNumbers;
    if (numbers.isEmpty) {
      return Text(
        'Hotline numbers for ${_selectedRegion.displayName} will be added '
        'soon.',
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textNavy,
          height: 1.4,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final number in numbers)
          InkWell(
            key: ValueKey('support-hotline-number-$number'),
            onTap: () => _onCallHotline(number),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textNavy,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
