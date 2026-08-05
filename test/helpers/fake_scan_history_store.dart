// Fake ScanHistoryStore for tests that exercise Scan Stock's history
// append behavior and the Scan History screen's rendering without touching
// the real shared_preferences platform channel.

import 'dart:async';

import 'package:anc_fabrics/services/last_scan_store.dart';
import 'package:anc_fabrics/services/scan_history_store.dart';

class FakeScanHistoryStore implements ScanHistoryStore {
  FakeScanHistoryStore({List<PersistedScanRecord>? initial})
    : _records = List.of(initial ?? const []);

  final List<PersistedScanRecord> _records;

  int appendCallCount = 0;
  int readCallCount = 0;

  /// When `true`, [append] silently fails to record (mirroring
  /// [ScanHistoryStore]'s real contract: every implementation catches its
  /// own persistence errors internally and never lets [append] throw — see
  /// `SharedPreferencesScanHistoryStore`) — lets a test verify a failed
  /// history write never hides a successful lookup result.
  bool simulateAppendFailure = false;

  int failedAppendCount = 0;

  /// When set, [read] throws this instead of returning — lets a test verify
  /// the Scan History screen degrades safely if local storage is entirely
  /// unreadable.
  Object? throwOnRead;

  /// When set, [read] does not complete until this completer completes —
  /// lets a test observe the Scan History screen's loading state instead of
  /// [read] resolving within the same microtask.
  Completer<void>? readGate;

  @override
  Future<List<PersistedScanRecord>> read() async {
    readCallCount++;
    if (readGate != null) await readGate!.future;
    final error = throwOnRead;
    if (error != null) throw error;
    final sorted = List<PersistedScanRecord>.of(_records)
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return List.unmodifiable(sorted);
  }

  @override
  Future<void> append(PersistedScanRecord record) async {
    appendCallCount++;
    if (simulateAppendFailure) {
      failedAppendCount++;
      return;
    }
    _records.add(record);
  }
}
