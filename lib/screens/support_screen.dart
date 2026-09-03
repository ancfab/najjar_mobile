import 'package:flutter/material.dart';

import '../data/support_regions_data.dart';
import '../localization/translations.dart';
import '../models/support_region.dart';
import '../navigation/main_bottom_nav.dart';
import '../services/auth_service.dart';
import '../services/phone_launcher.dart';
import '../services/support_region_service.dart';
import '../services/whatsapp_launcher.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/client_brand_title.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/support_action_card.dart';
import '../widgets/support_hours_card.dart';
import '../widgets/support_info_card.dart';
import '../widgets/support_office_location_tile.dart';
import '../widgets/support_region_selector.dart';
import 'contact_us_screen.dart';

/// Support landing screen: intro copy, a region selector, and region-scoped
/// contact cards (live chat/email, corporate office, direct hotline, and
/// support hours).
///
/// Region data is loaded through [SupportRegionService] (currently local
/// [kSupportRegions] data — see that class's doc comment for the CMS/API
/// contract this is pending on). If the load fails or returns no regions,
/// the screen falls back to [kSupportRegions] rather than getting stuck or
/// crashing.
///
/// TODO: Contact details (email, office address, hotline numbers, support
/// hours) are not yet verified for any region — see
/// `lib/data/support_regions_data.dart` for where to plug in confirmed
/// values. WhatsApp is already wired to `WhatsAppLauncher` and hotline
/// numbers are wired to `PhoneLauncher`, but both still show a "not yet
/// available" message per region until real contact numbers are populated.
class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    WhatsAppLauncher? whatsAppLauncher,
    PhoneLauncher? phoneLauncher,
    this.regions,
    SupportRegionService? regionService,
    this.authService,
  }) : whatsAppLauncher = whatsAppLauncher ?? const WhatsAppLauncher(),
       phoneLauncher = phoneLauncher ?? const PhoneLauncher(),
       regionService = regionService ?? const SupportRegionService();

  /// Injectable so tests can supply a fake launcher instead of touching the
  /// real `url_launcher` plugin.
  final WhatsAppLauncher whatsAppLauncher;

  /// Injectable so tests can supply a fake launcher instead of touching the
  /// real `url_launcher` plugin.
  final PhoneLauncher phoneLauncher;

  /// Injectable so tests can supply a fixed region list synchronously —
  /// e.g. to exercise the "WhatsApp number available" launch flow with a
  /// test-only region, since no production region has a verified
  /// `whatsappNumber` yet. Null in production, where regions are instead
  /// loaded asynchronously through [regionService].
  final List<SupportRegionData>? regions;

  /// Loads region-specific Support content when [regions] isn't supplied
  /// directly. Defaults to [SupportRegionService].
  final SupportRegionService regionService;

  /// Session seam used only to read the authenticated user's login country
  /// (via [AuthService.currentSession] — display/prefill only, never an
  /// auth check) so the initial region selection can default to it. Defaults
  /// (lazily, in State — see [_SupportScreenState]) to
  /// [AuthService.production]; overridable so tests can inject an
  /// [AuthService] wired to a fake session store instead of touching real
  /// secure storage.
  final AuthService? authService;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<SupportRegionData> _regions = const [];
  SupportRegionId? _selectedRegionId;
  bool _isLoadingRegions = true;
  bool _isWhatsAppLaunching = false;
  bool _isPhoneLaunching = false;

  late final AuthService _authService;

  /// Whether this instance created [_authService] itself (via
  /// [AuthService.production]) as opposed to receiving a caller-injected
  /// one — only an owned service is closed by [dispose].
  late final bool _ownsAuthService;

  // The region list and the session's login country load independently and
  // in either order (see _loadRegions/_loadSessionRegion). Whichever
  // resolves first applies the best default it can (see
  // _resolveDefaultRegionId); if the session then resolves afterward with a
  // recognized country, the default is upgraded — unless the user has
  // already made a manual choice (_hasManualSelection), which always wins.
  //
  // This intentionally does not block the loading spinner on the session
  // lookup: AuthService.currentSession() reads real secure storage by
  // default, whose platform channel never resolves in a widget test unless
  // a fake session store is injected (see feedback_pumpandsettle_perpetual
  // _spinner) — gating _isLoadingRegions on it would hang pumpAndSettle()
  // for every caller that doesn't inject one, including production.
  bool _regionsReady = false;
  bool _sessionReady = false;
  SupportRegionId? _sessionRegionId;
  bool _hasManualSelection = false;

  SupportRegionData get _selectedRegion => _regions.firstWhere(
    (region) => region.id == _selectedRegionId,
    orElse: () => _regions.first,
  );

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

    _loadSessionRegion();

    final overrideRegions = widget.regions;
    if (overrideRegions != null) {
      _applyLoadedRegions(overrideRegions);
    } else {
      _loadRegions();
    }
  }

  @override
  void dispose() {
    if (_ownsAuthService) _authService.close();
    super.dispose();
  }

  /// Reads the authenticated user's login country (display/prefill only —
  /// never used to decide authentication, see [AuthService.currentSession]'s
  /// doc comment) and maps it to a Support region via
  /// [SupportRegionId.fromCountryIsoCode]. A missing session, a session with
  /// no/unrecognized country (e.g. an older persisted session), or a
  /// storage read failure all safely resolve to no default (`null`) here —
  /// [_resolveDefaultRegionId] then falls back to the first region.
  ///
  /// Deliberately never gates [_isLoadingRegions]: this may not resolve at
  /// all in production if secure storage genuinely hangs, and must not
  /// leave the whole screen stuck loading over a prefill-only lookup.
  Future<void> _loadSessionRegion() async {
    SupportRegionId? regionId;
    try {
      final session = await _authService.currentSession();
      regionId = SupportRegionId.fromCountryIsoCode(session?.country);
    } catch (_) {
      regionId = null;
    }
    if (!mounted) return;
    setState(() {
      _sessionReady = true;
      _sessionRegionId = regionId;
      // Only upgrades a default already applied by _applyLoadedRegions —
      // never overrides a manual pick, and does nothing yet if regions
      // haven't loaded (that load will apply this once it does).
      if (_regionsReady && !_hasManualSelection) {
        _selectedRegionId = _resolveDefaultRegionId();
      }
    });
  }

  Future<void> _loadRegions() async {
    setState(() => _isLoadingRegions = true);
    List<SupportRegionData> loaded;
    try {
      loaded = await widget.regionService.fetchSupportRegions();
    } catch (_) {
      // A CMS/API outage falls back to the bundled local data rather than
      // leaving the Support screen stuck or crashed.
      loaded = kSupportRegions;
    }
    if (!mounted) return;
    _applyLoadedRegions(loaded.isNotEmpty ? loaded : kSupportRegions);
  }

  void _applyLoadedRegions(List<SupportRegionData> regions) {
    setState(() {
      _regions = regions;
      _regionsReady = true;
      _isLoadingRegions = false;
      if (!_hasManualSelection) {
        _selectedRegionId = _resolveDefaultRegionId();
      }
    });
  }

  /// The best region default available right now: the login country's
  /// region when the session has already resolved to one that's present in
  /// [_regions], otherwise the first region — matching the screen's prior
  /// unconditional default. Only meaningful once [_regionsReady] is true.
  SupportRegionId _resolveDefaultRegionId() {
    final sessionRegionId = _sessionRegionId;
    final hasSessionRegion =
        _sessionReady &&
        sessionRegionId != null &&
        _regions.any((region) => region.id == sessionRegionId);
    return hasSessionRegion ? sessionRegionId : _regions.first.id;
  }

  void _selectRegion(SupportRegionId regionId) {
    setState(() {
      _hasManualSelection = true;
      _selectedRegionId = regionId;
    });
  }

  Future<void> _onChatOnWhatsApp() async {
    if (_isWhatsAppLaunching) return;

    // Read the region fresh at tap time (not captured earlier) so a region
    // switch before this async work resolves can't use stale contact data.
    final region = _selectedRegion;
    final number = region.whatsappNumber;
    if (number == null || number.trim().isEmpty) {
      _showSnackBar(
        context.t(
          'support.whatsappUnavailable',
          params: {'region': region.id.localizedName(context)},
        ),
      );
      return;
    }

    setState(() => _isWhatsAppLaunching = true);
    try {
      final result = await widget.whatsAppLauncher.open(number);
      if (!mounted) return;
      if (!result.succeeded) {
        _showSnackBar(
          context.t(
            'support.whatsappOpenFailed',
            params: {'region': region.id.localizedName(context)},
          ),
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

  // Handles the shared bottom tab bar's taps — see main_bottom_nav.dart.
  // This screen is itself the Support tab's destination, so Support is
  // kept as the selected tab.
  void _handleBottomNavTap(int tabIndex) {
    handleMainBottomNavTap(
      context,
      tabIndex,
      ownTabIndex: kMainNavIndexSupport,
    );
  }

  void _onEmailSupport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactUsScreen(region: _selectedRegion),
      ),
    );
  }

  Future<void> _onCallOfficeLocation(String number) async {
    if (_isPhoneLaunching) return;

    setState(() => _isPhoneLaunching = true);
    try {
      final result = await widget.phoneLauncher.call(number);
      if (!mounted) return;
      if (!result.succeeded) {
        _showSnackBar(context.t('support.dialerUnavailable'));
      }
    } finally {
      if (mounted) setState(() => _isPhoneLaunching = false);
    }
  }

  Future<void> _onCallHotline(String number) async {
    if (_isPhoneLaunching) return;

    setState(() => _isPhoneLaunching = true);
    try {
      final result = await widget.phoneLauncher.call(number);
      if (!mounted) return;
      switch (result.outcome) {
        case PhoneLaunchOutcome.launched:
          break;
        case PhoneLaunchOutcome.unavailable:
          _showSnackBar(context.t('support.hotlineUnavailable'));
        case PhoneLaunchOutcome.failed:
          _showSnackBar(context.t('support.dialerUnavailable'));
      }
    } finally {
      if (mounted) setState(() => _isPhoneLaunching = false);
    }
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
        title: ClampedTextScale(
          child: ClientBrandTitle(pageTitle: context.t('support.title')),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ResponsiveMaxWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildIntro(),
                      const SizedBox(height: 20),
                      if (_isLoadingRegions)
                        _buildRegionsLoading()
                      else ...[
                        SupportRegionSelector(
                          key: const ValueKey('support-region-selector'),
                          regions: _regions,
                          selectedRegionId: _selectedRegionId!,
                          onRegionSelected: _selectRegion,
                        ),
                        const SizedBox(height: 20),
                        SupportActionCard(
                          onChatOnWhatsApp: _onChatOnWhatsApp,
                          onEmailSupport: _onEmailSupport,
                        ),
                        const SizedBox(height: 20),
                        SupportInfoCard(
                          key: const ValueKey('support-corporate-office-card'),
                          icon: Icons.apartment_rounded,
                          label: context.t('support.corporateOfficeLabel'),
                          child: _buildCorporateOfficeContent(),
                        ),
                        const SizedBox(height: 16),
                        SupportInfoCard(
                          key: const ValueKey('support-hotline-card'),
                          icon: Icons.call_rounded,
                          label: context.t('support.directHotlineLabel'),
                          child: _buildHotlineContent(),
                        ),
                        const SizedBox(height: 16),
                        SupportHoursCard(
                          key: const ValueKey('support-hours-card'),
                          scheduleText:
                              _selectedRegion.supportHours ??
                              context.t(
                                'support.hoursFallback',
                                params: {
                                  'region': _selectedRegion.id.localizedName(
                                    context,
                                  ),
                                },
                              ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            CustomBottomNav(
              currentIndex: kMainNavIndexSupport,
              onTap: _handleBottomNavTap,
            ),
          ],
        ),
      ),
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
                context.t('support.tag'),
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
          context.t('support.heroHeading'),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textNavy,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.t('support.intro'),
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.grayText,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildRegionsLoading() {
    return const Padding(
      key: ValueKey('support-regions-loading'),
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildCorporateOfficeContent() {
    final locations = _selectedRegion.officeLocations;
    if (locations.isEmpty) {
      return Text(
        context.t(
          'support.officeDetailsFallback',
          params: {'region': _selectedRegion.id.localizedName(context)},
        ),
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
        for (final location in locations) ...[
          SupportOfficeLocationTile(
            key: ValueKey('support-office-location-${location.city}'),
            location: location,
            onCallTap: _onCallOfficeLocation,
            compact: true,
            callNumberLabelKey: 'support.callNumber',
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildHotlineContent() {
    final numbers = _selectedRegion.hotlineNumbers;
    if (numbers.isEmpty) {
      return Text(
        context.t(
          'support.hotlineFallback',
          params: {'region': _selectedRegion.id.localizedName(context)},
        ),
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
          Semantics(
            button: true,
            label: context.t('support.callNumber', params: {'number': number}),
            child: InkWell(
              key: ValueKey('support-hotline-number-$number'),
              onTap: () => _onCallHotline(number),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Directionality(
                  textDirection: TextDirection.ltr,
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
            ),
          ),
      ],
    );
  }
}
