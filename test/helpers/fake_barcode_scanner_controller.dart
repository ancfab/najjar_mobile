// Fake BarcodeScannerController for tests that exercise the Scan Stock
// screen's scanning/torch/lifecycle behavior without depending on a real
// camera or the mobile_scanner platform channel.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:anc_fabrics/services/barcode_scanner_controller.dart';

class FakeBarcodeScannerController implements BarcodeScannerController {
  FakeBarcodeScannerController({
    this.startResult = ScanStartResult.success,
    ScanTorchState initialTorchState = ScanTorchState.off,
  }) : _torchState = ValueNotifier(initialTorchState);

  /// What [start] reports next time it's called.
  ScanStartResult startResult;

  /// Test seam: when set, [start] suspends on this completer instead of
  /// returning immediately, so a test can pump a frame while start() is
  /// still pending and assert on what's in the widget tree at that moment
  /// (e.g. that the preview widget is already mounted, matching what real
  /// mobile_scanner requires before start() is allowed to succeed).
  Completer<void>? startGate;

  final ValueNotifier<ScanTorchState> _torchState;
  final StreamController<ScanResult> _detectionsController =
      StreamController<ScanResult>.broadcast();

  int startCallCount = 0;
  int stopCallCount = 0;
  int toggleTorchCallCount = 0;
  int disposeCallCount = 0;
  bool isDisposed = false;

  /// Test seam: simulate the camera detecting [rawValue].
  void emit(String rawValue) {
    _detectionsController.add(ScanResult(rawValue));
  }

  /// Test seam: directly force the reported torch state (e.g. to simulate
  /// an unavailable torch).
  set torchStateValue(ScanTorchState value) => _torchState.value = value;

  @override
  Stream<ScanResult> get detections => _detectionsController.stream;

  @override
  ValueListenable<ScanTorchState> get torchState => _torchState;

  @override
  Future<ScanStartResult> start() async {
    startCallCount++;
    final gate = startGate;
    if (gate != null) {
      await gate.future;
    }
    return startResult;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> toggleTorch() async {
    toggleTorchCallCount++;
    if (_torchState.value == ScanTorchState.unavailable) return;
    _torchState.value = _torchState.value == ScanTorchState.on
        ? ScanTorchState.off
        : ScanTorchState.on;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    isDisposed = true;
    await _detectionsController.close();
    _torchState.dispose();
  }

  @override
  Widget buildPreview() {
    return const ColoredBox(
      key: ValueKey('fake-scanner-preview'),
      color: Color(0xFF000000),
    );
  }
}
