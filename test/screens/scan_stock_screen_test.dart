// Widget checks for the Scan Stock screen: header content (back
// navigation, localized title, torch control), the camera-permission
// state machine (granted/denied/permanently denied/restricted), scanner
// initialization (success/failure/unsupported), the QR frame and its
// corner/scan-line animations, the shared stock-lookup state machine
// (loading/success/not-found/invalid/retryable-failure/unavailable/mapping-
// not-configured, staleness and concurrency guards, Scan Again), the
// manual-entry fallback (validation, submission, cancel), Recent Scan
// persistence/restore, torch toggling, app-lifecycle pause/resume,
// controller disposal, and overflow safety across locales, an increased
// text scale, and landscape.
//
// Every real platform seam (camera permission, camera/scanner session,
// stock lookup, last-scan persistence) is injected as a fake — no real
// camera, platform channel, or backend call is touched.
//
// ScanStockScreen's QR-frame corners/scan-line run a perpetually repeating
// AnimationController, so every pump here uses a bounded `tester.pump(...)`
// rather than `pumpAndSettle()`, which would never return.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/screens/scan_history_screen.dart';
import 'package:anc_fabrics/screens/scan_stock_screen.dart';
import 'package:anc_fabrics/services/barcode_scanner_controller.dart';
import 'package:anc_fabrics/services/last_scan_store.dart';
import 'package:anc_fabrics/services/scan_camera_permission_service.dart';
import 'package:anc_fabrics/services/scan_history_store.dart';
import 'package:anc_fabrics/services/stock_lookup_service.dart';
import 'package:anc_fabrics/theme/app_colors.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

import '../helpers/fake_barcode_scanner_controller.dart';
import '../helpers/fake_last_scan_store.dart';
import '../helpers/fake_scan_camera_permission_service.dart';
import '../helpers/fake_scan_history_store.dart';
import '../helpers/fake_stock_lookup_service.dart';

const _titleByLocale = {
  'en': 'Scan Stock',
  'ar': 'مسح المخزون',
  'fr': 'Scanner le stock',
};

const _instructionByLocale = {
  'en': 'Center the QR code within the frame',
  'ar': 'ضع رمز الاستجابة السريعة في وسط الإطار',
  'fr': 'Centrez le code QR dans le cadre',
};

const _emptyStateByLocale = {
  'en': 'No recent scans yet',
  'ar': 'لا توجد عمليات مسح حتى الآن',
  'fr': 'Aucun scan récent',
};

const _cornerAlignments = [
  Alignment.topLeft,
  Alignment.topRight,
  Alignment.bottomLeft,
  Alignment.bottomRight,
];

const _retryButtonKey = ValueKey('scan-stock-retry-button');
const _openSettingsButtonKey = ValueKey('scan-stock-open-settings-button');
const _torchButtonKey = ValueKey('scan-stock-torch-button');
const _scanAgainButtonKey = ValueKey('scan-stock-scan-again-button');
const _qrFrameKey = ValueKey('scan-stock-qr-frame');
const _activeCodeKey = ValueKey('scan-stock-active-code');
const _loadingPanelKey = ValueKey('scan-stock-loading-panel');
const _resultCardKey = ValueKey('scan-stock-result-card');
const _notFoundPanelKey = ValueKey('scan-stock-not-found-panel');
const _invalidCodePanelKey = ValueKey('scan-stock-invalid-code-panel');
const _retryFailurePanelKey = ValueKey('scan-stock-retry-failure-panel');
const _unavailablePanelKey = ValueKey('scan-stock-unavailable-panel');
const _mappingNotConfiguredPanelKey = ValueKey(
  'scan-stock-mapping-not-configured-panel',
);
const _lookupRetryButtonKey = ValueKey('scan-stock-lookup-retry-button');
const _manualEntryButtonKey = ValueKey('scan-stock-manual-entry-button');
const _manualEntryFromResultButtonKey = ValueKey(
  'scan-stock-manual-entry-from-result-button',
);
const _manualEntrySheetKey = ValueKey('scan-stock-manual-entry-sheet');
const _manualEntryFieldKey = ValueKey('scan-stock-manual-entry-field');
const _manualEntryCancelKey = ValueKey('scan-stock-manual-entry-cancel');
const _manualEntrySubmitKey = ValueKey('scan-stock-manual-entry-submit');
const _recentScanEmptyKey = ValueKey('scan-stock-recent-scan-empty');
const _recentScanSummaryKey = ValueKey('scan-stock-recent-scan-summary');

/// A [StockLookupSuccess] fixture with every optional field populated,
/// including a two-location availability breakdown.
StockLookupSuccess _fullSuccess(String rawCode) => StockLookupSuccess(
  rawCode,
  scannedAt: DateTime.utc(2026, 7, 31, 10),
  itemNo: 'ITEM-0042',
  description: 'Egyptian Cotton Sateen (600TC)',
  availabilityByLocation: const [
    StockLocationAvailability(
      locationCode: 'BEIRUT',
      remainingQuantity: 150,
      unitOfMeasureCode: 'MT',
    ),
    StockLocationAvailability(
      locationCode: 'TRIPOLI',
      remainingQuantity: 20,
      unitOfMeasureCode: 'MT',
    ),
  ],
);

Future<void> _pumpScanStockScreen(
  WidgetTester tester, {
  String locale = 'en',
  double width = 390,
  double height = 800,
  double textScaleFactor = 1.0,
  ScanCameraPermissionService? permissionService,
  BarcodeScannerController? scannerController,
  StockLookupService? stockLookupService,
  LastScanStore? lastScanStore,
  ScanHistoryStore? scanHistoryStore,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: textScaleFactor == 1.0
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
              child: child!,
            ),
      home: ScanStockScreen(
        permissionService:
            permissionService ?? FakeScanCameraPermissionService(),
        scannerController: scannerController ?? FakeBarcodeScannerController(),
        stockLookupService: stockLookupService ?? FakeStockLookupService(),
        lastScanStore: lastScanStore ?? FakeLastScanStore(),
        scanHistoryStore: scanHistoryStore ?? FakeScanHistoryStore(),
      ),
    ),
  );
  // Drains the permission-check -> scanner-start async chain: each stage
  // is a separately awaited Future, so even fakes that resolve immediately
  // need more than one pump to fully settle. pumpAndSettle is avoided
  // throughout this file because the QR-frame animation repeats forever.
  await tester.pump();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('Screen opens', () {
    testWidgets('Screen opens successfully with no exceptions', (tester) async {
      await _pumpScanStockScreen(tester);

      expect(find.byType(ScanStockScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Header', () {
    testWidgets('Back button exists when reached via navigation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScanStockScreen(
                        permissionService: FakeScanCameraPermissionService(),
                        scannerController: FakeBarcodeScannerController(),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open'));
      // Bounded pumps for the push transition, not pumpAndSettle (see file
      // header note on the perpetual QR-frame animation).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ScanStockScreen), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Localized title exists', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(find.text('Scan Stock'), findsOneWidget);
    });

    testWidgets('Torch control exists', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(find.byKey(_torchButtonKey), findsOneWidget);
      expect(find.byTooltip('Toggle flash'), findsOneWidget);
    });
  });

  group('Camera permission', () {
    testWidgets('Permission granted shows the live scanning UI', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester);

      expect(find.byKey(_qrFrameKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scan-stock-camera-preview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Permission denied shows a localized message and Retry', (
      tester,
    ) async {
      final permission = FakeScanCameraPermissionService(
        status: ScanCameraPermissionStatus.denied,
      );
      await _pumpScanStockScreen(tester, permissionService: permission);

      expect(
        find.text(
          'Camera access was denied. Allow camera access to scan stock.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(_retryButtonKey), findsOneWidget);
      expect(permission.requestCount, 1);
    });

    testWidgets('Retry re-requests the permission', (tester) async {
      final permission = FakeScanCameraPermissionService(
        status: ScanCameraPermissionStatus.denied,
      );
      await _pumpScanStockScreen(tester, permissionService: permission);

      permission.status = ScanCameraPermissionStatus.granted;
      await tester.tap(find.byKey(_retryButtonKey));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(permission.requestCount, 2);
      expect(find.byKey(_qrFrameKey), findsOneWidget);
    });

    testWidgets(
      'Permission permanently denied shows a localized message and Open '
      'Settings',
      (tester) async {
        final permission = FakeScanCameraPermissionService(
          status: ScanCameraPermissionStatus.permanentlyDenied,
        );
        await _pumpScanStockScreen(tester, permissionService: permission);

        expect(
          find.text(
            'Camera access is permanently denied. Enable it in Settings to '
            'scan stock.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(_openSettingsButtonKey), findsOneWidget);
        expect(find.byKey(_retryButtonKey), findsNothing);
      },
    );

    testWidgets('Open Settings action opens the app settings', (tester) async {
      final permission = FakeScanCameraPermissionService(
        status: ScanCameraPermissionStatus.permanentlyDenied,
      );
      await _pumpScanStockScreen(tester, permissionService: permission);

      await tester.tap(find.byKey(_openSettingsButtonKey));
      await tester.pump();

      expect(permission.openSettingsCallCount, 1);
    });

    testWidgets(
      'Permission restricted shows a localized message with no action',
      (tester) async {
        final permission = FakeScanCameraPermissionService(
          status: ScanCameraPermissionStatus.restricted,
        );
        await _pumpScanStockScreen(tester, permissionService: permission);

        expect(
          find.text('Camera access is restricted on this device.'),
          findsOneWidget,
        );
        expect(find.byKey(_retryButtonKey), findsNothing);
        expect(find.byKey(_openSettingsButtonKey), findsNothing);
      },
    );
  });

  group('Scanner initialization', () {
    testWidgets('Initialization failure shows a localized message and Retry', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController(
        startResult: ScanStartResult.failure,
      );
      await _pumpScanStockScreen(tester, scannerController: scanner);

      expect(find.text('The scanner failed to start.'), findsOneWidget);
      expect(find.byKey(_retryButtonKey), findsOneWidget);

      scanner.startResult = ScanStartResult.success;
      await tester.tap(find.byKey(_retryButtonKey));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_qrFrameKey), findsOneWidget);
    });

    testWidgets('Unsupported device shows a localized message with no retry', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController(
        startResult: ScanStartResult.unsupported,
      );
      await _pumpScanStockScreen(tester, scannerController: scanner);

      expect(
        find.text('The scanner is unavailable on this device.'),
        findsOneWidget,
      );
      expect(find.byKey(_retryButtonKey), findsNothing);
    });

    testWidgets(
      'The preview widget is mounted before start() is called, not after '
      'it resolves — real mobile_scanner requires its widget to already be '
      'attached to the controller when start() runs',
      (tester) async {
        final scanner = FakeBarcodeScannerController()
          ..startGate = Completer<void>();
        await _pumpScanStockScreen(tester, scannerController: scanner);

        // start() has been invoked and is still pending (gated on
        // startGate), yet the preview widget must already be in the tree —
        // otherwise the real mobile_scanner controller would still be
        // waiting on its widget's initState to call attach().
        expect(scanner.startCallCount, 1);
        expect(
          find.byKey(const ValueKey('scan-stock-camera-preview')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('scan-stock-initializing-scanner')),
          findsOneWidget,
        );

        scanner.startGate!.complete();
        await tester.pump();
        await tester.pump();

        expect(find.byKey(_qrFrameKey), findsOneWidget);
      },
    );
  });

  group('Scan frame', () {
    testWidgets('Scan frame exists', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(find.byKey(_qrFrameKey), findsOneWidget);
    });

    testWidgets('Animated scan line exists', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(
        find.byKey(const ValueKey('scan-stock-scan-line')),
        findsOneWidget,
      );
    });

    testWidgets('Corner animation widgets exist for all four corners', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester);
      for (final alignment in _cornerAlignments) {
        expect(
          find.byKey(ValueKey('scan-stock-corner-$alignment')),
          findsOneWidget,
          reason: 'Missing animated corner for $alignment',
        );
      }
    });

    testWidgets('Scan line moves between frames of the repeating animation', (
      tester,
    ) async {
      // This test environment reports reduced motion by default (so the
      // screen's own reduced-motion handling correctly keeps the frame
      // static); opt out here specifically to verify the scan line
      // actually moves when motion isn't reduced.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await _pumpScanStockScreen(tester);
      final firstPosition = tester.getTopLeft(
        find.byKey(const ValueKey('scan-stock-scan-line-indicator')),
      );

      await tester.pump(const Duration(milliseconds: 600));
      final secondPosition = tester.getTopLeft(
        find.byKey(const ValueKey('scan-stock-scan-line-indicator')),
      );

      expect(secondPosition.dy, isNot(firstPosition.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Scan line stays static when reduce-motion is enabled', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await _pumpScanStockScreen(tester);
      final firstPosition = tester.getTopLeft(
        find.byKey(const ValueKey('scan-stock-scan-line-indicator')),
      );

      await tester.pump(const Duration(milliseconds: 600));
      final secondPosition = tester.getTopLeft(
        find.byKey(const ValueKey('scan-stock-scan-line-indicator')),
      );

      expect(secondPosition.dy, firstPosition.dy);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Instruction exists', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(find.text('Center the QR code within the frame'), findsOneWidget);
    });
  });

  group('Stock lookup — camera/barcode detection', () {
    testWidgets('QR decode triggers exactly one lookup call', (tester) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService();
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('https://ancfab.example/qr/ITEM-42');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(lookup.callCount, 1);
      expect(lookup.calls.single, 'https://ancfab.example/qr/ITEM-42');
    });

    testWidgets('Barcode decode triggers the same lookup', (tester) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService();
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('012345678905');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(lookup.callCount, 1);
      expect(lookup.calls.single, '012345678905');
    });

    testWidgets('Whitespace around the decoded value is trimmed', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService();
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('  ITEM-99  ');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(lookup.calls.single, 'ITEM-99');
    });

    testWidgets('Empty scan is ignored', (tester) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService();
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('   ');
      await tester.pump();

      expect(lookup.callCount, 0);
      expect(scanner.stopCallCount, 0);
      expect(find.byKey(_qrFrameKey), findsOneWidget);
    });

    testWidgets(
      'Duplicate scans of the same value do not re-trigger a lookup',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()..gate = Completer<void>();
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );

        scanner.emit('DUPLICATE-001');
        await tester.pump();
        expect(scanner.stopCallCount, 1);
        expect(lookup.callCount, 1);

        scanner.emit('DUPLICATE-001');
        await tester.pump();
        expect(scanner.stopCallCount, 1, reason: 'should not stop again');
        expect(lookup.callCount, 1, reason: 'should not look up again');
      },
    );

    testWidgets('Concurrent lookups are prevented for two different codes', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()..gate = Completer<void>();
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      // Both emitted before any pump, so the second arrives while the
      // first lookup is still in flight (gated).
      scanner.emit('CODE-A');
      scanner.emit('CODE-B');
      await tester.pump();
      await tester.pump();

      expect(lookup.callCount, 1);
      expect(lookup.calls, ['CODE-A']);
    });

    testWidgets('Loading state shows a spinner and the code, kept LTR', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()..gate = Completer<void>();
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('ITEM-LOADING');
      await tester.pump();

      expect(find.byKey(_loadingPanelKey), findsOneWidget);
      expect(find.text('Looking up stock…'), findsOneWidget);
      expect(find.text('ITEM-LOADING'), findsOneWidget);
      final context = tester.element(find.byKey(_activeCodeKey));
      expect(Directionality.of(context), TextDirection.ltr);
    });

    testWidgets('Success with every field shows all result rows', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()
        ..defaultResultBuilder = _fullSuccess;
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('ITEM-0042');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_resultCardKey), findsOneWidget);
      expect(find.text('Egyptian Cotton Sateen (600TC)'), findsOneWidget);
      expect(find.text('ITEM-0042'), findsWidgets);
      expect(
        find.byKey(const ValueKey('scan-stock-availability-section')),
        findsOneWidget,
      );
      expect(find.text('BEIRUT'), findsOneWidget);
      // BEIRUT's 150 MT is above the 100 m low-stock threshold: shown as
      // "Available" only — the exact quantity must never be rendered.
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('TRIPOLI'), findsOneWidget);
      // TRIPOLI's 20 MT is at/below the 100 m low-stock threshold: the exact
      // quantity must not be shown, only the localized contact-support copy.
      expect(find.text('Contact Support for inquiries'), findsOneWidget);
      expect(find.textContaining('150'), findsNothing);
      expect(find.textContaining('20 MT'), findsNothing);

      final beirutRowContainer = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('scan-stock-availability-row-0')),
          matching: find.byType(Container),
        ),
      );
      expect(
        (beirutRowContainer.decoration as BoxDecoration).color,
        AppColors.mint,
      );
      final tripoliRowContainer = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('scan-stock-availability-row-1')),
          matching: find.byType(Container),
        ),
      );
      expect(
        (tripoliRowContainer.decoration as BoxDecoration).color,
        AppColors.warningYellow,
      );
    });

    testWidgets('Success with optional fields missing hides those rows', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()
        ..defaultResultBuilder = (code) => StockLookupSuccess(
          code,
          scannedAt: DateTime.utc(2026, 1, 1),
          itemNo: 'ITEM-1',
        );
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('ITEM-1');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_resultCardKey), findsOneWidget);
      expect(find.text('ITEM-1'), findsWidgets);
      expect(find.text('Batch / Reference'), findsNothing);
      expect(find.text('Item / Fabric'), findsNothing);
      expect(
        find.byKey(const ValueKey('scan-stock-availability-section')),
        findsNothing,
      );
    });

    group('Low-stock (<= 100 m) hides the quantity', () {
      Future<void> pumpWithQuantity(
        WidgetTester tester,
        num remainingQuantity,
      ) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()
          ..defaultResultBuilder = (code) => StockLookupSuccess(
            code,
            scannedAt: DateTime.utc(2026, 1, 1),
            itemNo: 'ITEM-THRESHOLD',
            availabilityByLocation: [
              StockLocationAvailability(
                locationCode: 'BEIRUT',
                remainingQuantity: remainingQuantity,
                unitOfMeasureCode: 'MT',
              ),
            ],
          );
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );
        scanner.emit('ITEM-THRESHOLD');
        await tester.pump();
        await tester.pump();
        await tester.pump();
      }

      testWidgets('99 m shows Contact Support, not the quantity, with a '
          'yellow row background', (tester) async {
        await pumpWithQuantity(tester, 99);

        expect(find.text('Contact Support for inquiries'), findsOneWidget);
        expect(find.text('Available'), findsNothing);
        expect(find.textContaining('99'), findsNothing);
        final rowContainer = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('scan-stock-availability-row-0')),
            matching: find.byType(Container),
          ),
        );
        expect(
          (rowContainer.decoration as BoxDecoration).color,
          AppColors.warningYellow,
        );
      });

      testWidgets('100 m (the boundary) shows Contact Support, not the '
          'quantity, with a yellow row background', (tester) async {
        await pumpWithQuantity(tester, 100);

        expect(find.text('Contact Support for inquiries'), findsOneWidget);
        expect(find.text('Available'), findsNothing);
        expect(find.textContaining('100'), findsNothing);
        final rowContainer = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('scan-stock-availability-row-0')),
            matching: find.byType(Container),
          ),
        );
        expect(
          (rowContainer.decoration as BoxDecoration).color,
          AppColors.warningYellow,
        );
      });

      testWidgets('100.01 m shows Available without the real quantity, with '
          'a green row background', (tester) async {
        await pumpWithQuantity(tester, 100.01);

        expect(find.text('Available'), findsOneWidget);
        expect(find.textContaining('100.01'), findsNothing);
        expect(find.text('Contact Support for inquiries'), findsNothing);
        final rowContainer = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('scan-stock-availability-row-0')),
            matching: find.byType(Container),
          ),
        );
        expect(
          (rowContainer.decoration as BoxDecoration).color,
          AppColors.mint,
        );
      });

      testWidgets('150 m shows Available without the real quantity, with a '
          'green row background', (tester) async {
        await pumpWithQuantity(tester, 150);

        expect(find.text('Available'), findsOneWidget);
        expect(find.textContaining('150'), findsNothing);
        expect(find.text('Contact Support for inquiries'), findsNothing);
        final rowContainer = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('scan-stock-availability-row-0')),
            matching: find.byType(Container),
          ),
        );
        expect(
          (rowContainer.decoration as BoxDecoration).color,
          AppColors.mint,
        );
      });

      testWidgets('a non-meters unit at or below 100 shows Available '
          'without its quantity, and keeps the default (no colored) row '
          'background — the MT threshold/green-yellow visual rule must not '
          'apply to it (the threshold is meters-specific)', (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()
          ..defaultResultBuilder = (code) => StockLookupSuccess(
            code,
            scannedAt: DateTime.utc(2026, 1, 1),
            itemNo: 'ITEM-YD',
            availabilityByLocation: const [
              StockLocationAvailability(
                locationCode: 'BEIRUT',
                remainingQuantity: 15,
                unitOfMeasureCode: 'YD',
              ),
            ],
          );
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );
        scanner.emit('ITEM-YD');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Available'), findsOneWidget);
        expect(find.textContaining('15'), findsNothing);
        expect(find.text('Contact Support for inquiries'), findsNothing);
        // No MT-threshold styling: the row must not be wrapped in the
        // colored Container that MT rows get — it must not "become green"
        // just because it isn't low stock.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('scan-stock-availability-row-0')),
            matching: find.byType(Container),
          ),
          findsNothing,
        );
      });

      testWidgets('a non-meters unit above 100 also keeps the default (no '
          'colored) row background — never green from this feature', (
        tester,
      ) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()
          ..defaultResultBuilder = (code) => StockLookupSuccess(
            code,
            scannedAt: DateTime.utc(2026, 1, 1),
            itemNo: 'ITEM-PCS',
            availabilityByLocation: const [
              StockLocationAvailability(
                locationCode: 'BEIRUT',
                remainingQuantity: 20,
                unitOfMeasureCode: 'PCS',
              ),
            ],
          );
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );
        scanner.emit('ITEM-PCS');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Available'), findsOneWidget);
        expect(find.textContaining('20 PCS'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('scan-stock-availability-row-0')),
            matching: find.byType(Container),
          ),
          findsNothing,
        );
      });
    });

    testWidgets(
      'Not found shows the code, message, Scan Again, and Manual Entry',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()
          ..queuedResults.add(const StockLookupNotFound('MISSING-001'));
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );

        scanner.emit('MISSING-001');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.byKey(_notFoundPanelKey), findsOneWidget);
        expect(
          find.text('No stock result was found for "MISSING-001".'),
          findsOneWidget,
        );
        expect(find.byKey(_scanAgainButtonKey), findsOneWidget);
        expect(find.byKey(_manualEntryFromResultButtonKey), findsOneWidget);
      },
    );

    testWidgets(
      'Invalid code shows a validation message distinct from an API failure',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()
          ..queuedResults.add(const StockLookupInvalidCode('###'));
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );

        scanner.emit('###');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.byKey(_invalidCodePanelKey), findsOneWidget);
        expect(
          find.text("That code isn't valid. Please check it and try again."),
          findsOneWidget,
        );
      },
    );

    testWidgets('Retryable failure shows localized error copy and Retry', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(const StockLookupRetryableFailure('ITEM-ERR'));
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('ITEM-ERR');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_retryFailurePanelKey), findsOneWidget);
      expect(
        find.text("Couldn't load stock. Please try again."),
        findsOneWidget,
      );
      expect(find.byKey(_lookupRetryButtonKey), findsOneWidget);
    });

    testWidgets('Temporarily unavailable shows localized copy and Retry', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(
          const StockLookupTemporarilyUnavailable('ITEM-DOWN'),
        );
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('ITEM-DOWN');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_unavailablePanelKey), findsOneWidget);
      expect(
        find.text('Temporarily unavailable. Please try again shortly.'),
        findsOneWidget,
      );
      expect(find.byKey(_lookupRetryButtonKey), findsOneWidget);
    });

    testWidgets('The default UnconfiguredStockLookupService shows a controlled '
        'localized message', (tester) async {
      final scanner = FakeBarcodeScannerController();
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: const UnconfiguredStockLookupService(),
      );

      scanner.emit('ITEM-ANY');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_mappingNotConfiguredPanelKey), findsOneWidget);
      expect(
        find.text("Stock lookup isn't configured for this code yet."),
        findsOneWidget,
      );
    });

    testWidgets('Retry re-invokes the lookup for the same code', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(const StockLookupRetryableFailure('ITEM-ERR'));
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('ITEM-ERR');
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(lookup.callCount, 1);

      await tester.tap(find.byKey(_lookupRetryButtonKey));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(lookup.callCount, 2);
      expect(lookup.calls, ['ITEM-ERR', 'ITEM-ERR']);
      // The queue was drained by the first call, so the retry resolves via
      // the default (success) builder.
      expect(find.byKey(_resultCardKey), findsOneWidget);
    });

    testWidgets(
      'A result that resolves after the screen is disposed is ignored '
      'without error',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()..gate = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ScanStockScreen(
                          permissionService: FakeScanCameraPermissionService(),
                          scannerController: scanner,
                          stockLookupService: lookup,
                          lastScanStore: FakeLastScanStore(),
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.pump();

        scanner.emit('STALE-CODE');
        await tester.pump();
        expect(lookup.callCount, 1);

        Navigator.of(tester.element(find.byType(ScanStockScreen))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 1));

        // Resolves after dispose: must not call setState on an unmounted
        // State and must not throw.
        lookup.gate!.complete();
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Scan again clears the active result, resumes scanning, and keeps '
      'the persisted Recent Scan record',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final store = FakeLastScanStore();
        final lookup = FakeStockLookupService()
          ..defaultResultBuilder = _fullSuccess;
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
          lastScanStore: store,
        );

        scanner.emit('ITEM-0001');
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(_resultCardKey), findsOneWidget);
        expect(scanner.startCallCount, 1);
        expect(store.saveCallCount, 1);

        await tester.tap(find.byKey(_scanAgainButtonKey));
        await tester.pump();

        expect(find.byKey(_resultCardKey), findsNothing);
        expect(find.byKey(_qrFrameKey), findsOneWidget);
        expect(scanner.startCallCount, 2);
        // "Scan again" clears the active result only, not the persisted
        // Recent Scan record.
        expect(await store.read(), isNotNull);

        // The same value can be detected again after an explicit resume.
        scanner.emit('ITEM-0001');
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(_resultCardKey), findsOneWidget);
      },
    );

    testWidgets('A successful result is persisted to the last-scan store', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final store = FakeLastScanStore();
      final lookup = FakeStockLookupService()
        ..defaultResultBuilder = _fullSuccess;
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
        lastScanStore: store,
      );

      scanner.emit('ITEM-0042');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(store.saveCallCount, 1);
      final saved = await store.read();
      expect(saved!.rawCode, 'ITEM-0042');
      expect(saved.itemNo, 'ITEM-0042');
      expect(saved.description, 'Egyptian Cotton Sateen (600TC)');
      // No documented inventory field represents a batch reference — the
      // persisted record's batchReference stays null.
      expect(saved.batchReference, isNull);
    });

    testWidgets(
      'A successful camera lookup appends one history record and still '
      'updates the Recent Scan card — both represent the same event',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lastScanStore = FakeLastScanStore();
        final historyStore = FakeScanHistoryStore();
        final lookup = FakeStockLookupService()
          ..defaultResultBuilder = _fullSuccess;
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
          lastScanStore: lastScanStore,
          scanHistoryStore: historyStore,
        );

        scanner.emit('ITEM-0042');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(historyStore.appendCallCount, 1);
        final history = await historyStore.read();
        expect(history, hasLength(1));
        expect(history.single.rawCode, 'ITEM-0042');
        expect(history.single.itemNo, 'ITEM-0042');
        expect(history.single.description, 'Egyptian Cotton Sateen (600TC)');

        // Recent Scan and the latest history record represent the same
        // successful event.
        final recent = await lastScanStore.read();
        expect(recent!.rawCode, history.single.rawCode);
        expect(recent.scannedAt, history.single.scannedAt);
        expect(find.byKey(_recentScanSummaryKey), findsOneWidget);
      },
    );

    testWidgets('A failed history write does not hide the successful result or '
        'break the Recent Scan card', (tester) async {
      final scanner = FakeBarcodeScannerController();
      final historyStore = FakeScanHistoryStore()..simulateAppendFailure = true;
      final lookup = FakeStockLookupService()
        ..defaultResultBuilder = _fullSuccess;
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
        scanHistoryStore: historyStore,
      );

      scanner.emit('ITEM-0042');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_resultCardKey), findsOneWidget);
      expect(find.byKey(_recentScanSummaryKey), findsOneWidget);
      expect(historyStore.failedAppendCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A not-found result does not append to history', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final historyStore = FakeScanHistoryStore();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(const StockLookupNotFound('MISSING'));
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
        scanHistoryStore: historyStore,
      );

      scanner.emit('MISSING');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(historyStore.appendCallCount, 0);
    });

    testWidgets('An invalid-code result does not append to history', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final historyStore = FakeScanHistoryStore();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(const StockLookupInvalidCode('###'));
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
        scanHistoryStore: historyStore,
      );

      scanner.emit('###');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(historyStore.appendCallCount, 0);
    });

    testWidgets(
      'A retryable failure (e.g. HTTP 502) does not append to history',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final historyStore = FakeScanHistoryStore();
        final lookup = FakeStockLookupService()
          ..queuedResults.add(const StockLookupRetryableFailure('ITEM-502'));
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
          scanHistoryStore: historyStore,
        );

        scanner.emit('ITEM-502');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(historyStore.appendCallCount, 0);
      },
    );

    testWidgets(
      'A temporarily-unavailable failure (e.g. HTTP 503) does not append '
      'to history',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final historyStore = FakeScanHistoryStore();
        final lookup = FakeStockLookupService()
          ..queuedResults.add(
            const StockLookupTemporarilyUnavailable('ITEM-503'),
          );
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
          scanHistoryStore: historyStore,
        );

        scanner.emit('ITEM-503');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(historyStore.appendCallCount, 0);
      },
    );

    testWidgets('A malformed/unexpected failure does not append to history', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      final historyStore = FakeScanHistoryStore();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(const StockLookupUnexpectedFailure('ITEM-BAD'));
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
        scanHistoryStore: historyStore,
      );

      scanner.emit('ITEM-BAD');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(historyStore.appendCallCount, 0);
    });

    testWidgets('A not-found result is never persisted', (tester) async {
      final scanner = FakeBarcodeScannerController();
      final store = FakeLastScanStore();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(const StockLookupNotFound('MISSING'));
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
        lastScanStore: store,
      );

      scanner.emit('MISSING');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(store.saveCallCount, 0);
      expect(await store.read(), isNull);
    });

    testWidgets('An invalid-code result is never persisted', (tester) async {
      final scanner = FakeBarcodeScannerController();
      final store = FakeLastScanStore();
      final lookup = FakeStockLookupService()
        ..queuedResults.add(const StockLookupInvalidCode('###'));
      await _pumpScanStockScreen(
        tester,
        scannerController: scanner,
        stockLookupService: lookup,
        lastScanStore: store,
      );

      scanner.emit('###');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(store.saveCallCount, 0);
    });

    testWidgets('Result code stays LTR under an Arabic locale', (tester) async {
      final scanner = FakeBarcodeScannerController();
      final lookup = FakeStockLookupService()
        ..defaultResultBuilder = _fullSuccess;
      await _pumpScanStockScreen(
        tester,
        locale: 'ar',
        scannerController: scanner,
        stockLookupService: lookup,
      );

      scanner.emit('ITM-0099-A');
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final context = tester.element(find.byKey(_activeCodeKey));
      expect(Directionality.of(context), TextDirection.ltr);
    });
  });

  group('Session expiry (401)', () {
    // A real StockLookupSessionExpired always arrives after the production
    // ApiStockLookupService has already handed off to the app's single
    // centralized SessionExpiryCoordinator (see
    // ApiStockLookupService's "Session handling" unit tests for proof that
    // handoff happens exactly once) — by the time this screen would see the
    // result, that coordinator has already cleared the secure session and
    // replaced the navigation stack with LoginScreen. This screen's only
    // remaining job is to never render a competing/misleading error state
    // on top of that.
    testWidgets(
      'Shows no error/retry panel and returns to the idle scanning state — '
      'never presented as an ordinary stock-lookup error',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService()
          ..queuedResults.add(const StockLookupSessionExpired('ITEM-EXPIRED'));
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );

        scanner.emit('ITEM-EXPIRED');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.byKey(_retryFailurePanelKey), findsNothing);
        expect(find.byKey(_unavailablePanelKey), findsNothing);
        expect(find.byKey(_notFoundPanelKey), findsNothing);
        expect(find.byKey(_invalidCodePanelKey), findsNothing);
        expect(find.byKey(_mappingNotConfiguredPanelKey), findsNothing);
        expect(find.byKey(_resultCardKey), findsNothing);
        expect(find.byKey(_lookupRetryButtonKey), findsNothing);
        // Idle content (the QR frame) is shown again rather than any
        // controlled error panel — there is nothing useful to show once the
        // coordinator has already navigated away.
        expect(find.byKey(_qrFrameKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Does not persist to the Recent Scan store — a dead session is never '
      'treated as a successful lookup',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final store = FakeLastScanStore();
        final lookup = FakeStockLookupService()
          ..queuedResults.add(const StockLookupSessionExpired('ITEM-EXPIRED'));
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
          lastScanStore: store,
        );

        scanner.emit('ITEM-EXPIRED');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(store.saveCallCount, 0);
      },
    );

    testWidgets(
      'Does not append to history — a dead session is never treated as a '
      'successful lookup',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final historyStore = FakeScanHistoryStore();
        final lookup = FakeStockLookupService()
          ..queuedResults.add(const StockLookupSessionExpired('ITEM-EXPIRED'));
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
          scanHistoryStore: historyStore,
        );

        scanner.emit('ITEM-EXPIRED');
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(historyStore.appendCallCount, 0);
      },
    );
  });

  group('Torch', () {
    testWidgets('Toggling the torch calls the controller and updates icon', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController(
        initialTorchState: ScanTorchState.off,
      );
      await _pumpScanStockScreen(tester, scannerController: scanner);

      expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);

      await tester.tap(find.byKey(_torchButtonKey));
      await tester.pump();

      expect(scanner.toggleTorchCallCount, 1);
      expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
    });

    testWidgets('Torch unavailable disables the control', (tester) async {
      final scanner = FakeBarcodeScannerController(
        initialTorchState: ScanTorchState.unavailable,
      );
      await _pumpScanStockScreen(tester, scannerController: scanner);

      final button = tester.widget<IconButton>(find.byKey(_torchButtonKey));
      expect(button.onPressed, isNull);
      expect(find.byTooltip('Torch unavailable'), findsOneWidget);
    });
  });

  group('Lifecycle', () {
    testWidgets('App inactive stops the camera; resumed restarts it', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      await _pumpScanStockScreen(tester, scannerController: scanner);
      expect(scanner.startCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(scanner.stopCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(scanner.startCallCount, 2);
    });

    testWidgets('Disposing the screen disposes the scanner controller', (
      tester,
    ) async {
      final scanner = FakeBarcodeScannerController();
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScanStockScreen(
                        permissionService: FakeScanCameraPermissionService(),
                        scannerController: scanner,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();

      expect(scanner.disposeCallCount, 0);

      Navigator.of(tester.element(find.byType(ScanStockScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The pop transition needs a bit more idle time than a single 300ms
      // pump to fully settle and unmount the popped route in this widget
      // tree (confirmed empirically); pumpAndSettle isn't an option here
      // since the app is still perpetually animating at this point.
      await tester.pump(const Duration(seconds: 1));

      expect(scanner.disposeCallCount, 1);
      expect(scanner.isDisposed, isTrue);
    });
  });

  group('Recent Scan section', () {
    testWidgets('Recent Scan section exists', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(find.text('RECENT SCAN'), findsOneWidget);
    });

    testWidgets('Fake "Indigo Denim - Batch #4421" text is no longer shown', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester);
      expect(find.text('Indigo Denim - Batch #4421'), findsNothing);
    });

    testWidgets('Localized empty recent-scan state appears', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(find.text('No recent scans yet'), findsOneWidget);
    });

    testWidgets('View History control exists', (tester) async {
      await _pumpScanStockScreen(tester);
      expect(find.text('View History'), findsOneWidget);
    });

    testWidgets(
      'Tapping View History opens the full-screen Scan History page',
      (tester) async {
        await _pumpScanStockScreen(tester);

        await tester.tap(find.text('View History'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ScanHistoryScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('The old "coming soon" SnackBar is no longer shown', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester);

      await tester.tap(find.text('View History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Scan history coming soon'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
      'A persisted last scan is restored and shown on reopen instead of '
      'the empty state',
      (tester) async {
        final store = FakeLastScanStore(
          initial: PersistedScanRecord(
            rawCode: 'RESTORED-001',
            scannedAt: DateTime.utc(2026, 1, 1, 9),
            itemNo: 'RESTORED-001',
            description: 'Restored Fabric',
          ),
        );
        await _pumpScanStockScreen(tester, lastScanStore: store);

        expect(find.byKey(_recentScanSummaryKey), findsOneWidget);
        expect(find.textContaining('Restored Fabric'), findsOneWidget);
        expect(find.byKey(_recentScanEmptyKey), findsNothing);
        expect(find.text('No recent scans yet'), findsNothing);
      },
    );
  });

  group('Manual entry', () {
    testWidgets('Manual entry control opens the modal', (tester) async {
      await _pumpScanStockScreen(tester);

      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(_manualEntrySheetKey), findsOneWidget);
      expect(find.text('Enter Code Manually'), findsOneWidget);
    });

    testWidgets('Empty input shows inline validation', (tester) async {
      await _pumpScanStockScreen(tester);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(_manualEntrySubmitKey));
      await tester.pump();

      expect(find.text('Please enter a code.'), findsOneWidget);
      expect(find.byKey(_manualEntrySheetKey), findsOneWidget);
    });

    testWidgets('Whitespace-only input shows the same empty-code validation', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(_manualEntryFieldKey), '    ');
      await tester.tap(find.byKey(_manualEntrySubmitKey));
      await tester.pump();

      expect(find.text('Please enter a code.'), findsOneWidget);
      expect(find.byKey(_manualEntrySheetKey), findsOneWidget);
    });

    testWidgets('Overly long input shows a too-long validation message', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(_manualEntryFieldKey), 'X' * 65);
      await tester.tap(find.byKey(_manualEntrySubmitKey));
      await tester.pump();

      expect(find.text('That code is too long.'), findsOneWidget);
      expect(find.byKey(_manualEntrySheetKey), findsOneWidget);
    });

    testWidgets('Alphanumeric and hyphenated input is accepted', (
      tester,
    ) async {
      final lookup = FakeStockLookupService();
      await _pumpScanStockScreen(tester, stockLookupService: lookup);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(_manualEntryFieldKey), 'ITEM-42-A/B');
      await tester.tap(find.byKey(_manualEntrySubmitKey));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(lookup.calls.single, 'ITEM-42-A/B');
    });

    testWidgets('Keyboard submission works', (tester) async {
      final lookup = FakeStockLookupService();
      await _pumpScanStockScreen(tester, stockLookupService: lookup);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(_manualEntryFieldKey), 'ITEM-KB');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();

      expect(lookup.calls.single, 'ITEM-KB');
      expect(find.byKey(_manualEntrySheetKey), findsNothing);
    });

    testWidgets('Duplicate submission is prevented', (tester) async {
      final lookup = FakeStockLookupService()..gate = Completer<void>();
      await _pumpScanStockScreen(tester, stockLookupService: lookup);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(_manualEntryFieldKey), 'ITEM-DUP');
      await tester.pump();

      await tester.tap(find.byKey(_manualEntrySubmitKey));
      await tester.pump();

      expect(lookup.callCount, 1);
      final submitButton = tester.widget<ElevatedButton>(
        find.byKey(_manualEntrySubmitKey),
      );
      expect(
        submitButton.onPressed,
        isNull,
        reason: 'submit disables itself immediately on a valid submission',
      );

      // A further tap on the now-disabled button must not start a second
      // lookup.
      await tester.tap(find.byKey(_manualEntrySubmitKey), warnIfMissed: false);
      await tester.pump();

      expect(lookup.callCount, 1);
    });

    testWidgets(
      'Manual entry calls the exact same StockLookupService as scanning',
      (tester) async {
        final scanner = FakeBarcodeScannerController();
        final lookup = FakeStockLookupService();
        await _pumpScanStockScreen(
          tester,
          scannerController: scanner,
          stockLookupService: lookup,
        );

        scanner.emit('FROM-SCAN');
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(_scanAgainButtonKey));
        await tester.pump();

        await tester.tap(find.byKey(_manualEntryButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byKey(_manualEntryFieldKey), 'FROM-MANUAL');
        await tester.tap(find.byKey(_manualEntrySubmitKey));
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(lookup.calls, ['FROM-SCAN', 'FROM-MANUAL']);
      },
    );

    testWidgets('A successful manual lookup appends one history record', (
      tester,
    ) async {
      final historyStore = FakeScanHistoryStore();
      final lookup = FakeStockLookupService()
        ..defaultResultBuilder = _fullSuccess;
      await _pumpScanStockScreen(
        tester,
        stockLookupService: lookup,
        scanHistoryStore: historyStore,
      );

      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(_manualEntryFieldKey), 'MANUAL-ITEM');
      await tester.tap(find.byKey(_manualEntrySubmitKey));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(historyStore.appendCallCount, 1);
      final history = await historyStore.read();
      expect(history.single.rawCode, 'MANUAL-ITEM');
    });

    testWidgets(
      'The modal closes after a valid submission, then loading/result '
      'states appear on the parent screen',
      (tester) async {
        final lookup = FakeStockLookupService()..gate = Completer<void>();
        await _pumpScanStockScreen(tester, stockLookupService: lookup);
        await tester.tap(find.byKey(_manualEntryButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.enterText(find.byKey(_manualEntryFieldKey), 'ITEM-77');
        await tester.tap(find.byKey(_manualEntrySubmitKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(_manualEntrySheetKey), findsNothing);
        expect(find.byKey(_loadingPanelKey), findsOneWidget);
        expect(find.text('ITEM-77'), findsOneWidget);

        lookup.gate!.complete();
        await tester.pump();
        await tester.pump();

        expect(find.byKey(_resultCardKey), findsOneWidget);
      },
    );

    testWidgets('Cancel closes the modal without starting a lookup', (
      tester,
    ) async {
      final lookup = FakeStockLookupService();
      await _pumpScanStockScreen(tester, stockLookupService: lookup);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(_manualEntryCancelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(_manualEntrySheetKey), findsNothing);
      expect(lookup.callCount, 0);
      expect(find.byKey(_qrFrameKey), findsOneWidget);
    });

    testWidgets('Text controller is disposed with the sheet', (tester) async {
      await _pumpScanStockScreen(tester);
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(_manualEntryCancelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    for (final locale in _titleByLocale.keys) {
      testWidgets('$locale: manual entry sheet renders without overflow', (
        tester,
      ) async {
        await _pumpScanStockScreen(tester, locale: locale);
        await tester.tap(find.byKey(_manualEntryButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(_manualEntrySheetKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('No overflow in landscape with the manual entry sheet open', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester, width: 800, height: 400);
      // The idle overlay sits in a scrollable column at this short height,
      // so the button may start outside the current viewport.
      await tester.ensureVisible(find.byKey(_manualEntryButtonKey));
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(_manualEntrySheetKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow at increased text scale with the sheet open', (
      tester,
    ) async {
      await _pumpScanStockScreen(tester, textScaleFactor: 1.5);
      await tester.ensureVisible(find.byKey(_manualEntryButtonKey));
      await tester.tap(find.byKey(_manualEntryButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(_manualEntrySheetKey), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  group('Localization', () {
    for (final locale in _titleByLocale.keys) {
      testWidgets('$locale: renders title, instruction, and empty state', (
        tester,
      ) async {
        await _pumpScanStockScreen(tester, locale: locale);

        expect(find.text(_titleByLocale[locale]!), findsOneWidget);
        expect(find.text(_instructionByLocale[locale]!), findsOneWidget);
        expect(find.text(_emptyStateByLocale[locale]!), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$locale: no overflow', (tester) async {
        await _pumpScanStockScreen(tester, locale: locale);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Arabic renders right-to-left', (tester) async {
      await _pumpScanStockScreen(tester, locale: 'ar');

      final context = tester.element(find.text('مسح المخزون'));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive / accessibility', () {
    testWidgets('No overflow at increased text scale', (tester) async {
      await _pumpScanStockScreen(tester, textScaleFactor: 1.5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in landscape orientation', (tester) async {
      await _pumpScanStockScreen(tester, width: 800, height: 400);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow in a short small-phone landscape', (tester) async {
      await _pumpScanStockScreen(tester, width: 568, height: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow on a large phone in portrait', (tester) async {
      await _pumpScanStockScreen(tester, width: 430, height: 932);
      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow on a small phone in portrait', (tester) async {
      await _pumpScanStockScreen(tester, width: 320, height: 568);
      expect(tester.takeException(), isNull);
    });
  });
}
