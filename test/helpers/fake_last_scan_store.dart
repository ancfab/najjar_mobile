// Fake LastScanStore for tests that exercise Scan Stock's Recent Scan
// persistence/restore behavior without touching the real shared_preferences
// platform channel.

import 'package:anc_fabrics/services/last_scan_store.dart';

class FakeLastScanStore implements LastScanStore {
  FakeLastScanStore({PersistedScanRecord? initial}) : _record = initial;

  PersistedScanRecord? _record;
  int saveCallCount = 0;

  @override
  Future<PersistedScanRecord?> read() async => _record;

  @override
  Future<void> save(PersistedScanRecord record) async {
    saveCallCount++;
    _record = record;
  }
}
