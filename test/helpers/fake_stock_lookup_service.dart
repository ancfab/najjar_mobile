// Fake StockLookupService for tests that exercise Scan Stock's lookup state
// machine (camera detection and manual entry alike) without depending on
// UnconfiguredStockLookupService's fixed "mapping not configured" result or
// any real backend call.

import 'dart:async';

import 'package:anc_fabrics/services/stock_lookup_service.dart';

class FakeStockLookupService implements StockLookupService {
  FakeStockLookupService();

  /// Queue of results to return, one per call, in order. If exhausted,
  /// [defaultResultBuilder] is used instead.
  final List<StockLookupResult> queuedResults = [];

  /// Falls back to this when [queuedResults] is empty; defaults to a
  /// [StockLookupSuccess] echoing the raw code, matching the common case
  /// tests want without configuring a queue for every call.
  StockLookupResult Function(String rawCode) defaultResultBuilder = (rawCode) =>
      StockLookupSuccess(rawCode, scannedAt: DateTime(2026, 1, 1));

  /// Every code [lookup] has been called with, in call order.
  final List<String> calls = [];

  /// When set, [lookup] does not complete until this completer completes —
  /// lets a test observe the loading state and control exactly when the
  /// lookup resolves (e.g. to test staleness/concurrency guards).
  Completer<void>? gate;

  int get callCount => calls.length;

  @override
  Future<StockLookupResult> lookup(String rawCode) async {
    calls.add(rawCode);
    if (gate != null) await gate!.future;
    if (queuedResults.isNotEmpty) return queuedResults.removeAt(0);
    return defaultResultBuilder(rawCode);
  }
}
