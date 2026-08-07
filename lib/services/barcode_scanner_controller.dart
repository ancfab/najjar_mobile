import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;

/// A single decoded QR/barcode value.
///
/// NOTE(stock-lookup): interpreting [rawValue] — deciding whether it is an
/// itemNo, commonItemNo, gtin, batch ID, or documentNo — is explicitly out
/// of scope here. That mapping belongs to the later stock-lookup
/// integration task, once the endpoint-side lookup contract is confirmed.
class ScanResult {
  const ScanResult(this.rawValue);

  final String rawValue;
}

/// Torch (flashlight) state, decoupled from any specific scanner package's
/// enum so the UI never imports a package-specific torch type.
enum ScanTorchState {
  /// The device has no torch, or the camera isn't running yet.
  unavailable,
  off,
  on,
}

/// Outcome of trying to start the scanner's camera session.
enum ScanStartResult {
  /// The camera started and is actively scanning.
  success,

  /// Scanning is not supported on this device (e.g. no camera hardware).
  unsupported,

  /// The camera failed to start for some other reason.
  failure,
}

/// Small, package-agnostic seam over the underlying QR/barcode scanner
/// package, so [ScanStockScreen] (and its widget tests) depend only on this
/// interface rather than embedding package-specific types/calls throughout
/// the UI.
///
/// Camera permission is expected to already be granted (see
/// [ScanCameraPermissionService]) before [start] is called — this
/// interface only owns the scanner session itself.
abstract class BarcodeScannerController {
  /// Emits one [ScanResult] per detected code. Does not de-duplicate;
  /// duplicate-scan suppression is the caller's responsibility.
  Stream<ScanResult> get detections;

  /// The current torch state, observable so the UI can reflect it (and
  /// disable the control when unavailable) without polling.
  ValueListenable<ScanTorchState> get torchState;

  /// Starts (or resumes) the camera session.
  Future<ScanStartResult> start();

  /// Stops/pauses the camera session; safe to call repeatedly. Can be
  /// restarted with [start].
  Future<void> stop();

  /// Toggles the torch. Does nothing if the torch is unavailable.
  Future<void> toggleTorch();

  /// Releases underlying platform camera resources. The controller must
  /// not be used after this is called.
  Future<void> dispose();

  /// Builds the live camera preview widget for this controller.
  Widget buildPreview();
}

/// Real [BarcodeScannerController] backed by the `mobile_scanner` plugin.
///
/// `autoStart` is deliberately false: [ScanStockScreen] only calls [start]
/// once camera permission has been confirmed granted, rather than letting
/// the widget request permission itself on mount.
class MobileScannerBarcodeScannerController
    implements BarcodeScannerController {
  MobileScannerBarcodeScannerController()
    : _controller = ms.MobileScannerController(autoStart: false) {
    _controller.addListener(_syncTorchState);
  }

  final ms.MobileScannerController _controller;
  final ValueNotifier<ScanTorchState> _torchStateNotifier = ValueNotifier(
    ScanTorchState.unavailable,
  );

  void _syncTorchState() {
    _torchStateNotifier.value = switch (_controller.value.torchState) {
      ms.TorchState.on => ScanTorchState.on,
      ms.TorchState.off => ScanTorchState.off,
      // `auto` (iOS/macOS-only: flash decided automatically) has no direct
      // manual on/off equivalent in this app's UI; treat it as off so the
      // toggle button always reflects a state the user can act on.
      ms.TorchState.auto => ScanTorchState.off,
      ms.TorchState.unavailable => ScanTorchState.unavailable,
    };
  }

  @override
  ValueListenable<ScanTorchState> get torchState => _torchStateNotifier;

  @override
  Stream<ScanResult> get detections => _controller.barcodes
      .expand((capture) => capture.barcodes)
      .map((barcode) => barcode.rawValue)
      .where((value) => value != null)
      .map((value) => ScanResult(value!));

  @override
  Future<ScanStartResult> start() async {
    try {
      await _controller.start();
    } catch (error) {
      // MobileScannerController.start() only catches platform-channel
      // failures internally (wrapping them into `_controller.value.error`
      // below); some of its own MobileScannerExceptions — notably
      // controllerNotAttached, thrown when start() is called before the
      // MobileScanner widget has attached this controller — and any
      // lower-level platform-channel failure (e.g. no plugin implementation
      // registered) still propagate out of start() and must not crash the
      // screen, but are worth surfacing here rather than discarding.
      debugPrint('MobileScannerController.start() threw: $error');
      return ScanStartResult.failure;
    }
    final error = _controller.value.error;
    if (error == null) return ScanStartResult.success;
    if (error.errorCode == ms.MobileScannerErrorCode.unsupported) {
      return ScanStartResult.unsupported;
    }
    return ScanStartResult.failure;
  }

  @override
  Future<void> stop() => _controller.stop();

  @override
  Future<void> toggleTorch() => _controller.toggleTorch();

  @override
  Future<void> dispose() async {
    _controller.removeListener(_syncTorchState);
    _torchStateNotifier.dispose();
    await _controller.dispose();
  }

  @override
  Widget buildPreview() => ms.MobileScanner(controller: _controller);
}
