import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../localization/translations.dart';
import '../services/api_stock_lookup_service.dart';
import '../services/barcode_scanner_controller.dart';
import '../services/last_scan_store.dart';
import '../services/scan_camera_permission_service.dart';
import '../services/scan_history_store.dart';
import '../services/stock_lookup_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/date_time_format.dart';
import '../utils/responsive.dart';
import 'scan_history_screen.dart';

/// The Scan Stock screen's current stage, driving which content
/// [_ScanPreviewArea] shows in place of (or alongside) the live preview.
enum _ScanStage {
  /// Requesting/checking the camera permission.
  checkingPermission,

  /// The user denied the permission; asking again is still possible.
  permissionDenied,

  /// The user denied the permission and the OS will not prompt again.
  permissionPermanentlyDenied,

  /// The OS denies the permission outright (e.g. parental controls/MDM).
  permissionRestricted,

  /// Permission is granted; the camera session is starting.
  initializingScanner,

  /// Scanning is not supported on this device (e.g. no camera hardware).
  scannerUnsupported,

  /// The camera failed to start for some other reason.
  scannerFailed,

  /// The camera is live and ready (a lookup may also be in progress or
  /// showing a result, per [_LookupStage]).
  ready,
}

/// The stock-lookup state machine driving what [_ScanPreviewArea] shows on
/// top of the live camera preview once [_ScanStage.ready] is reached. Shared
/// by both the camera/barcode detection path and the manual-entry fallback
/// — both call [_ScanStockScreenState._startLookup].
enum _LookupStage {
  /// No lookup in progress; the QR frame/instruction (and the manual-entry
  /// action) are shown.
  idle,

  /// A lookup is in flight for [_ScanStockScreenState._activeCode].
  loading,

  /// The lookup found a stock record.
  success,

  /// The lookup completed but found no stock record for the code.
  notFound,

  /// The code failed validation (distinct from an API failure).
  invalidCode,

  /// A transient failure occurred; retrying is reasonable.
  retryableFailure,

  /// The backing service reported itself temporarily unavailable.
  temporarilyUnavailable,

  /// No production stock-lookup adapter is configured yet — see
  /// [UnconfiguredStockLookupService].
  mappingNotConfigured,
}

/// Scan Stock screen: requests camera permission, then runs a live
/// QR/barcode scanner behind the existing animated frame overlay, resolving
/// a decoded (or manually typed) exact Business Central `itemNo` to
/// per-location stock availability through the shared [StockLookupService]
/// abstraction — this screen depends only on that abstraction, never
/// directly on `ApiStockLookupService`'s own dependencies
/// (`AncApiClient`/`SecureAuthSessionStore`/`SessionExpiryCoordinator`), so
/// swapping the production adapter or injecting a fake in tests requires no
/// change here beyond [stockLookupService].
class ScanStockScreen extends StatefulWidget {
  const ScanStockScreen({
    super.key,
    ScanCameraPermissionService? permissionService,
    this.scannerController,
    this.stockLookupService,
    LastScanStore? lastScanStore,
    ScanHistoryStore? scanHistoryStore,
  }) : permissionService =
           permissionService ??
           const PermissionHandlerScanCameraPermissionService(),
       lastScanStore = lastScanStore ?? const SharedPreferencesLastScanStore(),
       scanHistoryStore =
           scanHistoryStore ?? const SharedPreferencesScanHistoryStore();

  /// Camera permission seam. Overridable so tests can inject a fake
  /// instead of invoking the real platform permission channel.
  final ScanCameraPermissionService permissionService;

  /// Scanner/camera seam. Overridable so tests can inject a fake instead of
  /// invoking the real camera platform channel. Defaults (lazily, in
  /// State) to a real [MobileScannerBarcodeScannerController].
  final BarcodeScannerController? scannerController;

  /// Shared stock-lookup seam, called by both camera/barcode detection and
  /// manual entry. Left `null` here (rather than defaulted in this
  /// constructor) and resolved lazily in
  /// [_ScanStockScreenState.initState] instead: the production default,
  /// [ApiStockLookupService], owns a real `AncApiClient`/
  /// `SecureAuthSessionStore` that must be closed on [State.dispose] —
  /// mirroring `LoginScreen`'s `AuthService.production()` ownership
  /// pattern rather than constructing network infrastructure inside this
  /// widget's (potentially repeatedly-built) constructor. Overridable so
  /// tests can inject a fake instead of making a real network call.
  final StockLookupService? stockLookupService;

  /// Last-successful-scan persistence seam, backing the Recent Scan card.
  final LastScanStore lastScanStore;

  /// Scan-history persistence seam, backing the Scan History screen. Every
  /// [StockLookupSuccess] appends to this store in addition to updating
  /// [lastScanStore] — see [_ScanStockScreenState._startLookup].
  final ScanHistoryStore scanHistoryStore;

  @override
  State<ScanStockScreen> createState() => _ScanStockScreenState();
}

class _ScanStockScreenState extends State<ScanStockScreen>
    with WidgetsBindingObserver {
  late final BarcodeScannerController _scannerController =
      widget.scannerController ?? MobileScannerBarcodeScannerController();

  /// Stock-lookup seam actually used by [_startLookup] — resolved in
  /// [initState], not here; see [ScanStockScreen.stockLookupService]'s doc
  /// comment for why.
  late final StockLookupService _stockLookupService;

  /// Set only when this State created its own [ApiStockLookupService] (no
  /// [ScanStockScreen.stockLookupService] was injected) — the only instance
  /// this screen ever closes; a caller-injected [StockLookupService] is left
  /// alone since this screen doesn't own it.
  ApiStockLookupService? _ownedStockLookupService;

  _ScanStage _stage = _ScanStage.checkingPermission;
  _LookupStage _lookupStage = _LookupStage.idle;

  /// The raw value currently suppressed as "still in view", cleared by
  /// [_resumeScanning].
  String? _suppressedValue;

  bool _isProcessingDetection = false;

  /// True while a lookup is in flight — guards against a second lookup
  /// (from a race between camera detection and manual entry) starting
  /// concurrently.
  bool _isLookingUp = false;

  /// Bumped at the start of every [_startLookup] call, so a lookup that
  /// resolves after a newer one has already started (or after dispose) can
  /// recognize itself as stale and discard its result.
  int _lookupGeneration = 0;

  /// The code the current/most recent lookup is for, or null when
  /// [_lookupStage] is [_LookupStage.idle].
  String? _activeCode;

  /// The most recent lookup result, or null when [_lookupStage] is
  /// [_LookupStage.idle] or [_LookupStage.loading].
  StockLookupResult? _lookupResult;

  /// The persisted last successful scan, restored on open and updated after
  /// every new successful lookup — backs the Recent Scan card. Untouched by
  /// "Scan again" and by failed/invalid lookups.
  PersistedScanRecord? _recentScan;

  StreamSubscription<ScanResult>? _detectionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final injectedStockLookupService = widget.stockLookupService;
    if (injectedStockLookupService != null) {
      _stockLookupService = injectedStockLookupService;
    } else {
      final owned = ApiStockLookupService();
      _ownedStockLookupService = owned;
      _stockLookupService = owned;
    }
    _detectionSubscription = _scannerController.detections.listen(
      _handleDetection,
    );
    unawaited(_checkAndRequestPermission());
    unawaited(_restoreRecentScan());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Bumping the generation here means an in-flight lookup's continuation
    // recognizes itself as stale (see [_startLookup]) and never calls
    // setState after dispose.
    _lookupGeneration++;
    unawaited(_detectionSubscription?.cancel());
    unawaited(_scannerController.dispose());
    _ownedStockLookupService?.close();
    super.dispose();
  }

  Future<void> _restoreRecentScan() async {
    final record = await widget.lastScanStore.read();
    if (!mounted || record == null) return;
    setState(() => _recentScan = record);
  }

  static const _permissionStages = {
    _ScanStage.permissionDenied,
    _ScanStage.permissionPermanentlyDenied,
    _ScanStage.permissionRestricted,
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mirrors mobile_scanner's own internal lifecycle convention (stop on
    // `inactive`, restart on `resumed`) instead of reacting to `paused`
    // directly: `inactive` reliably precedes `paused` on the way to the
    // background, and `resumed` is the return signal — reacting to those
    // two is enough to never leave the camera running off-screen.
    switch (state) {
      case AppLifecycleState.inactive:
        if (_stage == _ScanStage.ready) {
          unawaited(_scannerController.stop());
        }
      case AppLifecycleState.resumed:
        unawaited(_handleResumed());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _handleResumed() async {
    if (!mounted) return;
    if (_permissionStages.contains(_stage)) {
      // The user may have changed the permission from the app's Settings
      // page; re-check rather than assuming it's still denied.
      await _checkAndRequestPermission();
      return;
    }
    if (_stage == _ScanStage.ready && _lookupStage == _LookupStage.idle) {
      await _scannerController.start();
    }
  }

  Future<void> _checkAndRequestPermission() async {
    if (!mounted) return;
    setState(() => _stage = _ScanStage.checkingPermission);
    final ScanCameraPermissionStatus status;
    try {
      status = await widget.permissionService.requestCameraPermission();
    } catch (error) {
      // An unexpected platform-channel failure must not crash the screen;
      // fall back to the same recoverable state as an explicit denial so
      // Retry remains available.
      debugPrint('Camera permission request failed: $error');
      if (mounted) setState(() => _stage = _ScanStage.permissionDenied);
      return;
    }
    if (!mounted) return;
    switch (status) {
      case ScanCameraPermissionStatus.granted:
        await _startScanner();
      case ScanCameraPermissionStatus.denied:
        setState(() => _stage = _ScanStage.permissionDenied);
      case ScanCameraPermissionStatus.permanentlyDenied:
        setState(() => _stage = _ScanStage.permissionPermanentlyDenied);
      case ScanCameraPermissionStatus.restricted:
        setState(() => _stage = _ScanStage.permissionRestricted);
    }
  }

  Future<void> _startScanner() async {
    if (!mounted) return;
    setState(() => _stage = _ScanStage.initializingScanner);

    // mobile_scanner requires its MobileScanner widget to already be
    // mounted (and to have attached this controller from its own
    // initState) before start() is called — otherwise start() waits for
    // that attachment and eventually times out with
    // MobileScannerErrorCode.controllerNotAttached. The _stage change above
    // puts the preview widget into the tree (see _ScanPreviewArea), but it
    // isn't actually built until the next frame; wait for that frame to
    // finish before starting.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final result = await _scannerController.start();
    if (!mounted) return;
    setState(() {
      _stage = switch (result) {
        ScanStartResult.success => _ScanStage.ready,
        ScanStartResult.unsupported => _ScanStage.scannerUnsupported,
        ScanStartResult.failure => _ScanStage.scannerFailed,
      };
    });
  }

  Future<void> _openSettings() => widget.permissionService.openSettings();

  void _handleDetection(ScanResult result) {
    // Guards against re-entrant handling of near-simultaneous detection
    // events; the stronger protection below (stopping the camera) is what
    // prevents further events from arriving at all.
    if (_isProcessingDetection) return;

    final trimmed = result.rawValue.trim();
    if (trimmed.isEmpty) return;
    if (trimmed == _suppressedValue) return;
    if (_isLookingUp) return;

    _isProcessingDetection = true;
    _suppressedValue = trimmed;

    unawaited(_startLookup(trimmed));
    _isProcessingDetection = false;
  }

  /// Resolves [code] through the shared [StockLookupService] — the single
  /// entry point both camera/barcode detection and manual entry call, so
  /// every stock lookup goes through exactly one implementation.
  Future<void> _startLookup(String code) async {
    if (_isLookingUp) return;
    _isLookingUp = true;
    final myGeneration = ++_lookupGeneration;

    // Pausing the controller is a stronger guarantee against duplicate/
    // rapid camera detections than a debounce timer: no further frames are
    // analyzed at all until the user explicitly resumes via "Scan again".
    // Also covers the manual-entry path: once a lookup is active, the
    // camera stays stopped until "Scan again". Safe to call repeatedly.
    unawaited(_scannerController.stop());

    if (mounted) {
      setState(() {
        _activeCode = code;
        _lookupResult = null;
        _lookupStage = _LookupStage.loading;
      });
    }

    StockLookupResult result;
    try {
      result = await _stockLookupService.lookup(code);
    } catch (error) {
      // A truly unexpected exception (an implementation bug) must not crash
      // the screen; treat it like any other unexpected failure.
      debugPrint('Stock lookup threw unexpectedly: $error');
      result = StockLookupUnexpectedFailure(code);
    }

    _isLookingUp = false;
    // Discards a response that arrived after a newer lookup started (or
    // after dispose bumped the generation) rather than overwriting fresher
    // state with stale data.
    if (!mounted || myGeneration != _lookupGeneration) return;

    if (result is StockLookupSuccess) {
      final record = PersistedScanRecord(
        rawCode: result.rawCode,
        scannedAt: result.scannedAt,
        itemNo: result.itemNo,
        description: result.description,
        batchReference: result.batchReference,
      );
      unawaited(widget.lastScanStore.save(record));
      unawaited(widget.scanHistoryStore.append(record));
      setState(() {
        _lookupResult = result;
        _lookupStage = _LookupStage.success;
        _recentScan = record;
      });
      return;
    }

    if (result is StockLookupSessionExpired) {
      // A real adapter is expected to hand off to the session coordinator
      // (which navigates to Login) before ever returning this — matching
      // `SessionExpiredException` elsewhere in the app, there is nothing
      // controlled to show here.
      setState(() {
        _activeCode = null;
        _lookupResult = null;
        _lookupStage = _LookupStage.idle;
      });
      return;
    }

    setState(() {
      _lookupResult = result;
      _lookupStage = _stageFor(result);
    });
  }

  static _LookupStage _stageFor(StockLookupResult result) => switch (result) {
    StockLookupSuccess() => _LookupStage.success,
    StockLookupNotFound() => _LookupStage.notFound,
    StockLookupInvalidCode() => _LookupStage.invalidCode,
    StockLookupRetryableFailure() => _LookupStage.retryableFailure,
    StockLookupTemporarilyUnavailable() => _LookupStage.temporarilyUnavailable,
    StockLookupMappingNotConfigured() => _LookupStage.mappingNotConfigured,
    StockLookupSessionExpired() => _LookupStage.idle,
    StockLookupUnexpectedFailure() => _LookupStage.retryableFailure,
  };

  Future<void> _retryLookup() async {
    final code = _activeCode;
    if (code == null) return;
    await _startLookup(code);
  }

  Future<void> _resumeScanning() async {
    setState(() {
      _activeCode = null;
      _lookupResult = null;
      _lookupStage = _LookupStage.idle;
      _suppressedValue = null;
    });
    await _scannerController.start();
  }

  Future<void> _openManualEntry() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ManualEntrySheet(
        onSubmit: (code) {
          Navigator.of(sheetContext).pop();
          unawaited(_startLookup(code));
        },
      ),
    );
  }

  Future<void> _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();
    } catch (error) {
      // Torch errors (e.g. a transient platform failure) must not crash
      // the screen; the torch-state ValueListenable already reflects
      // unavailability by disabling the control.
      debugPrint('Failed to toggle torch: $error');
    }
  }

  // Opens the full Scan History screen, backed by the same
  // scanHistoryStore every successful lookup appends to.
  void _openScanHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanHistoryScreen(
          historyStore: widget.scanHistoryStore,
          lastScanStore: widget.lastScanStore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      appBar: AppBar(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.t('scanStock.title')),
        actions: [
          ValueListenableBuilder<ScanTorchState>(
            valueListenable: _scannerController.torchState,
            builder: (context, torch, _) {
              final unavailable = torch == ScanTorchState.unavailable;
              return IconButton(
                key: const ValueKey('scan-stock-torch-button'),
                icon: Icon(
                  torch == ScanTorchState.on
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                ),
                tooltip: unavailable
                    ? context.t('scanStock.torchUnavailableTooltip')
                    : context.t('scanStock.toggleFlashTooltip'),
                onPressed: unavailable ? null : _toggleTorch,
              );
            },
          ),
        ],
      ),
      // The AppBar already accounts for the top inset, so only left/right/
      // bottom are left to SafeArea here — this matters in landscape, where
      // a device notch/rounded corner sits on a side edge instead of the top.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _ScanPreviewArea(
                stage: _stage,
                lookupStage: _lookupStage,
                lookupResult: _lookupResult,
                activeCode: _activeCode,
                scannerController: _scannerController,
                onRetryPermission: _checkAndRequestPermission,
                onOpenSettings: _openSettings,
                onScanAgain: _resumeScanning,
                onRetryLookup: _retryLookup,
                onManualEntry: _openManualEntry,
              ),
            ),
            _RecentScanCard(
              recentScan: _recentScan,
              onViewHistory: _openScanHistory,
            ),
          ],
        ),
      ),
    );
  }
}

// Full-bleed scanning viewport: either the live camera preview or a dark
// fallback layer (permission/init states, and widget tests), behind the
// centered QR frame/instruction overlay or a state-specific message panel.
class _ScanPreviewArea extends StatelessWidget {
  const _ScanPreviewArea({
    required this.stage,
    required this.lookupStage,
    required this.lookupResult,
    required this.activeCode,
    required this.scannerController,
    required this.onRetryPermission,
    required this.onOpenSettings,
    required this.onScanAgain,
    required this.onRetryLookup,
    required this.onManualEntry,
  });

  final _ScanStage stage;
  final _LookupStage lookupStage;
  final StockLookupResult? lookupResult;
  final String? activeCode;
  final BarcodeScannerController scannerController;
  final Future<void> Function() onRetryPermission;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onScanAgain;
  final Future<void> Function() onRetryLookup;
  final Future<void> Function() onManualEntry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Mounted from initializingScanner onward (not just once ready):
        // the underlying mobile_scanner widget must already be built and
        // have attached its controller before ScanStockScreen calls
        // start() — see _ScanStockScreenState._startScanner.
        if (stage == _ScanStage.initializingScanner ||
            stage == _ScanStage.ready)
          KeyedSubtree(
            key: const ValueKey('scan-stock-camera-preview'),
            child: scannerController.buildPreview(),
          )
        else
          const _CameraPreviewFallback(),
        Center(
          child: ResponsiveMaxWidth(
            maxWidth: 480,
            alignment: Alignment.center,
            child: CenteredScrollable(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.xxl,
              ),
              child: _buildOverlayContent(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayContent(BuildContext context) {
    switch (stage) {
      case _ScanStage.checkingPermission:
        return _StatusPanel(
          key: const ValueKey('scan-stock-checking-permission'),
          message: context.t('scanStock.permissionRequiredMessage'),
          showSpinner: true,
        );
      case _ScanStage.initializingScanner:
        return const _StatusPanel(
          key: ValueKey('scan-stock-initializing-scanner'),
          message: null,
          showSpinner: true,
        );
      case _ScanStage.permissionDenied:
        return _StatusPanel(
          key: const ValueKey('scan-stock-permission-denied'),
          message: context.t('scanStock.permissionDeniedMessage'),
          primaryActionLabel: context.t('scanStock.retryAction'),
          primaryActionKey: const ValueKey('scan-stock-retry-button'),
          onPrimaryAction: onRetryPermission,
        );
      case _ScanStage.permissionPermanentlyDenied:
        return _StatusPanel(
          key: const ValueKey('scan-stock-permission-permanently-denied'),
          message: context.t('scanStock.permissionPermanentlyDeniedMessage'),
          primaryActionLabel: context.t('scanStock.openSettingsAction'),
          primaryActionKey: const ValueKey('scan-stock-open-settings-button'),
          onPrimaryAction: onOpenSettings,
        );
      case _ScanStage.permissionRestricted:
        return _StatusPanel(
          key: const ValueKey('scan-stock-permission-restricted'),
          message: context.t('scanStock.permissionRestrictedMessage'),
        );
      case _ScanStage.scannerUnsupported:
        return _StatusPanel(
          key: const ValueKey('scan-stock-scanner-unsupported'),
          message: context.t('scanStock.scannerUnavailableMessage'),
        );
      case _ScanStage.scannerFailed:
        return _StatusPanel(
          key: const ValueKey('scan-stock-scanner-failed'),
          message: context.t('scanStock.scannerInitFailedMessage'),
          primaryActionLabel: context.t('scanStock.retryAction'),
          primaryActionKey: const ValueKey('scan-stock-retry-button'),
          onPrimaryAction: onRetryPermission,
        );
      case _ScanStage.ready:
        return _buildLookupContent(context);
    }
  }

  Widget _buildLookupContent(BuildContext context) {
    switch (lookupStage) {
      case _LookupStage.idle:
        return Column(
          key: const ValueKey('scan-stock-idle-content'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _QrFrame(),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              context.t('scanStock.centerQrInstruction'),
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextButton.icon(
              key: const ValueKey('scan-stock-manual-entry-button'),
              onPressed: () => onManualEntry(),
              icon: const Icon(
                Icons.keyboard_alt_outlined,
                color: Colors.white,
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              label: Text(
                context.t('scanStock.manualEntryAction'),
                style: AppTypography.buttonText,
              ),
            ),
          ],
        );
      case _LookupStage.loading:
        return _LookupLoadingPanel(code: activeCode ?? '');
      case _LookupStage.success:
        return _StockResultCard(
          result: lookupResult! as StockLookupSuccess,
          onScanAgain: onScanAgain,
        );
      case _LookupStage.notFound:
        // Even with no stock record, incoming stock already on a purchase
        // order surfaces its expected receipt date under the main message.
        final notFoundResult = lookupResult;
        final restockDate = notFoundResult is StockLookupNotFound
            ? notFoundResult.expectedRestockDate
            : null;
        final notFoundMessage = context.t(
          'scanStock.noStockFoundMessage',
          params: {'code': activeCode ?? ''},
        );
        return _LookupMessagePanel(
          key: const ValueKey('scan-stock-not-found-panel'),
          code: activeCode,
          message: restockDate == null
              ? notFoundMessage
              : '$notFoundMessage\n${context.t('home.stockExpectedBy', params: {'date': MaterialLocalizations.of(context).formatMediumDate(restockDate)})}',
          primaryActionLabel: context.t('scanStock.scanAgainAction'),
          primaryActionKey: const ValueKey('scan-stock-scan-again-button'),
          onPrimaryAction: onScanAgain,
          secondaryActionLabel: context.t('scanStock.manualEntryAction'),
          secondaryActionKey: const ValueKey(
            'scan-stock-manual-entry-from-result-button',
          ),
          onSecondaryAction: onManualEntry,
        );
      case _LookupStage.invalidCode:
        return _LookupMessagePanel(
          key: const ValueKey('scan-stock-invalid-code-panel'),
          code: activeCode,
          message: context.t('scanStock.invalidCodeMessage'),
          primaryActionLabel: context.t('scanStock.scanAgainAction'),
          primaryActionKey: const ValueKey('scan-stock-scan-again-button'),
          onPrimaryAction: onScanAgain,
        );
      case _LookupStage.retryableFailure:
        return _LookupMessagePanel(
          key: const ValueKey('scan-stock-retry-failure-panel'),
          code: activeCode,
          message: context.t('scanStock.lookupFailureMessage'),
          primaryActionLabel: context.t('scanStock.retryAction'),
          primaryActionKey: const ValueKey('scan-stock-lookup-retry-button'),
          onPrimaryAction: onRetryLookup,
        );
      case _LookupStage.temporarilyUnavailable:
        return _LookupMessagePanel(
          key: const ValueKey('scan-stock-unavailable-panel'),
          code: activeCode,
          message: context.t('scanStock.lookupUnavailableMessage'),
          primaryActionLabel: context.t('scanStock.retryAction'),
          primaryActionKey: const ValueKey('scan-stock-lookup-retry-button'),
          onPrimaryAction: onRetryLookup,
        );
      case _LookupStage.mappingNotConfigured:
        return _LookupMessagePanel(
          key: const ValueKey('scan-stock-mapping-not-configured-panel'),
          code: activeCode,
          message: context.t('scanStock.lookupMappingNotConfiguredMessage'),
          primaryActionLabel: context.t('scanStock.scanAgainAction'),
          primaryActionKey: const ValueKey('scan-stock-scan-again-button'),
          onPrimaryAction: onScanAgain,
        );
    }
  }
}

// Shared layout for permission/scanner status states: an optional spinner,
// an optional localized message, and an optional single action button.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    super.key,
    required this.message,
    this.showSpinner = false,
    this.primaryActionLabel,
    this.primaryActionKey,
    this.onPrimaryAction,
  });

  final String? message;
  final bool showSpinner;
  final String? primaryActionLabel;
  final Key? primaryActionKey;
  final Future<void> Function()? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showSpinner) ...[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white70,
            ),
          ),
          if (message != null) const SizedBox(height: AppSpacing.xl),
        ],
        if (message != null)
          Text(
            message!,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: Colors.white70),
          ),
        if (primaryActionLabel != null && onPrimaryAction != null) ...[
          const SizedBox(height: AppSpacing.xl),
          TextButton(
            key: primaryActionKey,
            onPressed: () => onPrimaryAction!(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
            ),
            child: Text(primaryActionLabel!, style: AppTypography.buttonText),
          ),
        ],
      ],
    );
  }
}

// Shown while a stock lookup is in flight: a spinner, a localized "looking
// up" message, and the technical code being looked up — kept visible and
// LTR even under Arabic.
class _LookupLoadingPanel extends StatelessWidget {
  const _LookupLoadingPanel({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('scan-stock-loading-panel'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          context.t('scanStock.lookupLoadingMessage'),
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: AppSpacing.md),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            code,
            key: const ValueKey('scan-stock-active-code'),
            textAlign: TextAlign.center,
            style: AppTypography.cardTitle.copyWith(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

// Generic panel for a completed-but-unsuccessful lookup (not found, invalid
// code, retryable/unavailable failure, mapping not configured): the
// technical code (LTR), a localized message, and up to two actions.
class _LookupMessagePanel extends StatelessWidget {
  const _LookupMessagePanel({
    super.key,
    required this.code,
    required this.message,
    required this.primaryActionLabel,
    required this.primaryActionKey,
    required this.onPrimaryAction,
    this.secondaryActionLabel,
    this.secondaryActionKey,
    this.onSecondaryAction,
  });

  final String? code;
  final String message;
  final String primaryActionLabel;
  final Key primaryActionKey;
  final Future<void> Function() onPrimaryAction;
  final String? secondaryActionLabel;
  final Key? secondaryActionKey;
  final Future<void> Function()? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mint.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (code != null && code!.isNotEmpty) ...[
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                code!,
                key: const ValueKey('scan-stock-active-code'),
                textAlign: TextAlign.center,
                style: AppTypography.cardTitle.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            message,
            key: const ValueKey('scan-stock-lookup-message'),
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(
                key: primaryActionKey,
                onPressed: () => onPrimaryAction(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                ),
                child: Text(
                  primaryActionLabel,
                  style: AppTypography.buttonText,
                ),
              ),
              if (secondaryActionLabel != null && onSecondaryAction != null)
                TextButton(
                  key: secondaryActionKey,
                  onPressed: () => onSecondaryAction!(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                  ),
                  child: Text(
                    secondaryActionLabel!,
                    style: AppTypography.buttonText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Responsive result card shown after a successful lookup: only the fields
// actually present in [result], the technical code/item number kept LTR, the
// per-location/unit availability breakdown, and a "Scan again" action.
class _StockResultCard extends StatelessWidget {
  const _StockResultCard({required this.result, required this.onScanAgain});

  final StockLookupSuccess result;
  final Future<void> Function() onScanAgain;

  @override
  Widget build(BuildContext context) {
    final rows = _rows(context);
    final availability = result.availabilityByLocation;

    return Container(
      key: const ValueKey('scan-stock-result-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mint.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('scanStock.stockResultTitle'),
            textAlign: TextAlign.center,
            style: AppTypography.label.copyWith(
              color: AppColors.mint,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              result.rawCode,
              key: const ValueKey('scan-stock-active-code'),
              textAlign: TextAlign.center,
              style: AppTypography.cardTitle.copyWith(color: Colors.white70),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final row in rows) ...[
            _ResultRow(data: row),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (availability.isNotEmpty) ...[
            Text(
              context.t('scanStock.availabilityByLocationLabel'),
              style: AppTypography.bodySecondary.copyWith(
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Column(
              key: const ValueKey('scan-stock-availability-section'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < availability.length; i++) ...[
                  _LocationAvailabilityRow(
                    key: ValueKey('scan-stock-availability-row-$i'),
                    availability: availability[i],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ],
          if (result.combinedAvailabilityLevel ==
                  StockAvailabilityLevel.outOfStock &&
              result.expectedRestockDate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              key: const ValueKey('scan-stock-expected-restock'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.warningYellow.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.t(
                  'home.stockExpectedBy',
                  params: {
                    'date': MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(result.expectedRestockDate!),
                  },
                ),
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary.copyWith(
                  color: AppColors.warningYellow,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            key: const ValueKey('scan-stock-scan-again-button'),
            onPressed: () => onScanAgain(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
            ),
            child: Text(
              context.t('scanStock.scanAgainAction'),
              style: AppTypography.buttonText,
            ),
          ),
        ],
      ),
    );
  }

  List<_ResultRowData> _rows(BuildContext context) {
    final description = result.description;
    final itemNo = result.itemNo;
    final batchReference = result.batchReference;

    return [
      if (description != null && description.isNotEmpty)
        _ResultRowData(context.t('scanStock.itemFabricLabel'), description),
      if (itemNo != null && itemNo.isNotEmpty)
        _ResultRowData(context.t('scanStock.itemNumberLabel'), itemNo),
      if (batchReference != null && batchReference.isNotEmpty)
        _ResultRowData(
          context.t('scanStock.batchReferenceLabel'),
          batchReference,
        ),
    ];
  }
}

// One row of the per-location/unit availability breakdown: the location
// code (or a localized "Unknown location" fallback when empty) and a
// localized "available"/"contact support" status label — never the actual
// remaining quantity, which must not be exposed to the user — kept LTR since
// the location code is a technical identifier.
//
// The MT threshold rule (`StockLocationAvailability.isLowStockInMeters`)
// only applies to meters entries — see [StockLocationAvailability
// .isMeasuredInMeters]'s doc comment for why `!isLowStockInMeters` must
// never be read as "available, render green": that's also `true` for a
// non-MT entry, which must keep its original/default styling instead of
// picking up a green background. So the row only gets a colored background
// for an MT entry — yellow (contact-support warning) at/below the
// threshold, green (available) above it; any other unit of measure renders
// with no background, exactly as before this MT-specific feature existed.
class _LocationAvailabilityRow extends StatelessWidget {
  const _LocationAvailabilityRow({super.key, required this.availability});

  final StockLocationAvailability availability;

  @override
  Widget build(BuildContext context) {
    final isMeters = availability.isMeasuredInMeters;
    final isLowStock = availability.isLowStockInMeters;
    final locationCode = availability.locationCode;
    final hasLocationCode = locationCode.isNotEmpty;
    final locationLabel = hasLocationCode
        ? locationCode
        : context.t('scanStock.unknownLocationLabel');
    final availableText = isLowStock
        ? context.t('common.contactSupportForInquiries')
        : context.t('common.available');

    final Color? backgroundColor = !isMeters
        ? null
        : (isLowStock ? AppColors.warningYellow : AppColors.mint);
    final foregroundColor = !isMeters
        ? Colors.white60
        : (isLowStock ? AppColors.darkAmber : AppColors.darkTeal);
    final quantityForegroundColor = !isMeters ? Colors.white : foregroundColor;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: hasLocationCode
              ? Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    locationLabel,
                    style: AppTypography.bodySecondary.copyWith(
                      color: foregroundColor,
                      fontWeight: isMeters ? FontWeight.w600 : null,
                    ),
                  ),
                )
              : Text(
                  locationLabel,
                  style: AppTypography.bodySecondary.copyWith(
                    color: foregroundColor,
                    fontWeight: isMeters ? FontWeight.w600 : null,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              availableText,
              textAlign: TextAlign.end,
              style: AppTypography.body.copyWith(
                color: quantityForegroundColor,
              ),
            ),
          ),
        ),
      ],
    );

    if (!isMeters) return row;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }
}

class _ResultRowData {
  const _ResultRowData(this.label, this.value);

  final String label;
  final String value;
}

// One label/value row within [_StockResultCard]. The value is always kept
// LTR: every field this card renders is either a technical identifier or a
// number, never free-form natural-language text.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.data});

  final _ResultRowData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            data.label,
            style: AppTypography.bodySecondary.copyWith(color: Colors.white60),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              data.value,
              textAlign: TextAlign.end,
              style: AppTypography.body.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// Modal bottom sheet for the manual-entry fallback: a code field and
// Cancel/Check Stock actions. Calls [onSubmit] with the trimmed, validated
// code — [ScanStockScreen] runs it through the exact same
// [StockLookupService.lookup] call as a camera/barcode detection.
class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet({required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  /// Defensive UI limit only — not a claim about any real code format (see
  /// [StockLookupService]'s doc comment on the unresolved code identity).
  static const int _maxLength = 64;

  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  /// Set as soon as a valid submission is accepted, disabling the submit
  /// button so a second tap (before the sheet finishes closing) can't start
  /// a duplicate lookup.
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_submitted) return;

    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(
        () => _errorText = context.t('scanStock.manualEntryEmptyValidation'),
      );
      return;
    }
    if (trimmed.length > _maxLength) {
      setState(
        () => _errorText = context.t('scanStock.manualEntryTooLongValidation'),
      );
      return;
    }

    setState(() {
      _submitted = true;
      _errorText = null;
    });
    widget.onSubmit(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        key: const ValueKey('scan-stock-manual-entry-sheet'),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.sheetTop,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('scanStock.manualEntryTitle'),
                  style: AppTypography.sectionTitle.copyWith(
                    color: AppColors.textNavy,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.t('scanStock.manualEntryDescription'),
                  style: AppTypography.bodySecondary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    key: const ValueKey('scan-stock-manual-entry-field'),
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleSubmit(),
                    decoration: InputDecoration(
                      labelText: context.t('scanStock.manualEntryFieldLabel'),
                      hintText: context.t('scanStock.manualEntryFieldHint'),
                      errorText: _errorText,
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.inputAll,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('scan-stock-manual-entry-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.t('common.cancel')),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton(
                        key: const ValueKey('scan-stock-manual-entry-submit'),
                        onPressed: _submitted ? null : _handleSubmit,
                        child: Text(
                          context.t('scanStock.manualEntrySubmitAction'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Dark full-screen placeholder standing in for the live camera preview
// while permission/init hasn't resolved to a ready scanner yet (and in
// widget tests, which never touch the real camera platform channel).
class _CameraPreviewFallback extends StatelessWidget {
  const _CameraPreviewFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey('scan-stock-camera-fallback'),
      color: AppColors.gradientNavyStart,
    );
  }
}

// Square framing overlay shown over the live preview to guide the user to
// center a QR code: a static border, corners with a subtle repeating
// pulse, and a scan line sweeping top-to-bottom, clipped to the frame's
// rounded bounds.
class _QrFrame extends StatefulWidget {
  const _QrFrame();

  static const double _size = 220;
  static const double _cornerLength = 28;
  static const double _cornerThickness = 4;
  static const double _borderRadius = 16;
  static const double _scanLineThickness = 3;

  @override
  State<_QrFrame> createState() => _QrFrameState();
}

class _QrFrameState extends State<_QrFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also covers the first build: didChangeDependencies always runs once
    // right after initState, before MediaQuery.of(context) is safe to call.
    _syncWithMotionPreference();
  }

  // Keeps the corner pulse and scan line static (rather than animating) when
  // the platform's "reduce motion" accessibility setting is on.
  void _syncWithMotionPreference() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('scan-stock-qr-frame'),
      width: _QrFrame._size,
      height: _QrFrame._size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          // A full sine cycle per loop: smooth and continuous even across
          // the point where the scan line itself snaps back to the top, so
          // the corner pulse never visibly jumps.
          final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * t);
          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 1),
                  borderRadius: BorderRadius.circular(_QrFrame._borderRadius),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(_QrFrame._borderRadius),
                child: _ScanLine(
                  key: const ValueKey('scan-stock-scan-line'),
                  progress: t,
                ),
              ),
              for (final alignment in const [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight,
              ])
                Align(
                  alignment: alignment,
                  child: _FrameCorner(
                    key: ValueKey('scan-stock-corner-$alignment'),
                    alignment: alignment,
                    pulse: pulse,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// The mint scan line swept between the top and bottom of the frame. Sized to
// the full frame and positioned via [progress] (0..1) so the parent's
// ClipRRect keeps it from ever rendering outside the frame's rounded bounds.
class _ScanLine extends StatelessWidget {
  const _ScanLine({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const travel = _QrFrame._size - _QrFrame._scanLineThickness;
    return SizedBox(
      width: _QrFrame._size,
      height: _QrFrame._size,
      child: Stack(
        children: [
          Positioned(
            top: progress * travel,
            left: 8,
            right: 8,
            child: Container(
              key: const ValueKey('scan-stock-scan-line-indicator'),
              height: _QrFrame._scanLineThickness,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  _QrFrame._scanLineThickness,
                ),
                gradient: LinearGradient(
                  colors: [
                    AppColors.mint.withValues(alpha: 0),
                    AppColors.mint,
                    AppColors.mint.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameCorner extends StatelessWidget {
  const _FrameCorner({super.key, required this.alignment, required this.pulse});

  final Alignment alignment;

  /// 0..1 pulse phase driving a soft opacity/glow pulse on this corner.
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    final opacity = 0.6 + 0.4 * pulse;
    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: AppColors.mint.withValues(alpha: 0.35 * pulse),
              blurRadius: 6 * pulse,
            ),
          ],
        ),
        child: SizedBox(
          width: _QrFrame._cornerLength,
          height: _QrFrame._cornerLength,
          child: Stack(
            children: [
              Positioned(
                top: isTop ? 0 : null,
                bottom: isTop ? null : 0,
                left: 0,
                right: 0,
                child: Container(
                  height: _QrFrame._cornerThickness,
                  color: Colors.white,
                ),
              ),
              Positioned(
                left: isLeft ? 0 : null,
                right: isLeft ? null : 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: _QrFrame._cornerThickness,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bottom card showing the most recent successful scan (persisted via
// [LastScanStore]) and a link to full history.
class _RecentScanCard extends StatelessWidget {
  const _RecentScanCard({
    required this.recentScan,
    required this.onViewHistory,
  });

  final PersistedScanRecord? recentScan;
  final void Function(BuildContext context) onViewHistory;

  @override
  Widget build(BuildContext context) {
    final record = recentScan;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.t('scanStock.recentScanLabel'),
                  style: AppTypography.label.copyWith(
                    color: AppColors.grayText,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (record == null)
                  Text(
                    context.t('scanStock.noRecentScans'),
                    key: const ValueKey('scan-stock-recent-scan-empty'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.cardTitle.copyWith(
                      color: AppColors.textNavy,
                    ),
                  )
                else ...[
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      _summaryText(record),
                      key: const ValueKey('scan-stock-recent-scan-summary'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.cardTitle.copyWith(
                        color: AppColors.textNavy,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${context.t('scanStock.lastSuccessfulScanLabel')}: '
                    '${formatCompactLocalTimestamp(record.scannedAt)}',
                    key: const ValueKey('scan-stock-recent-scan-timestamp'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: () => onViewHistory(context),
            child: Text(
              context.t('scanStock.viewHistoryButton'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// "{description or raw code} • {itemNo} • {batchReference}", each part
  /// only included when non-null/non-empty and not already shown.
  static String _summaryText(PersistedScanRecord record) {
    final parts = <String>[];
    final description = record.description;
    final primary = (description != null && description.isNotEmpty)
        ? description
        : record.rawCode;
    parts.add(primary);

    final itemNo = record.itemNo;
    if (itemNo != null && itemNo.isNotEmpty && itemNo != primary) {
      parts.add(itemNo);
    }
    final batchReference = record.batchReference;
    if (batchReference != null && batchReference.isNotEmpty) {
      parts.add(batchReference);
    }
    return parts.join(' • ');
  }
}
