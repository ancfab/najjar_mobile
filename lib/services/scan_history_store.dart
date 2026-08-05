import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'last_scan_store.dart';

/// Purpose: Local-device-only persistence for the Scan Stock history list —
/// every successful stock lookup (camera or manual entry), newest first,
/// capped at [SharedPreferencesScanHistoryStore.maxRecords] records.
///
/// Deliberately separate from [LastScanStore]: that store keeps exactly one
/// record for the Recent Scan card, while this one accumulates a bounded
/// list for the dedicated Scan History screen. Both are updated from the
/// same [PersistedScanRecord] built at the same successful-lookup call site
/// so they always represent the same latest event, but neither store reads
/// or writes the other's data.
///
/// CONFIRMED(scan-history contract, first release): local-device-only — no
/// scan-history API endpoint exists or is assumed. Reuses
/// [PersistedScanRecord] rather than a separate model since the history
/// screen displays exactly the same fields as the Recent Scan card (raw
/// code, timestamp, item number, description, batch/reference) and
/// deliberately excludes quantity/location/unit, same as that record.
abstract class ScanHistoryStore {
  /// Every stored record, newest [PersistedScanRecord.scannedAt] first.
  /// Returns an empty list if nothing has been saved yet, or the stored
  /// value could not be read back.
  Future<List<PersistedScanRecord>> read();

  /// Appends [record], re-sorts newest-first, and retains only the newest
  /// [SharedPreferencesScanHistoryStore.maxRecords] records.
  Future<void> append(PersistedScanRecord record);
}

/// Default [ScanHistoryStore], backed by `shared_preferences` — mirrors
/// [SharedPreferencesLastScanStore]'s precedent that a scan result's display
/// fields are not sensitive. Stored under its own versioned key, entirely
/// separate from [SharedPreferencesLastScanStore]'s single-record key, so
/// neither store's data ever overwrites the other's.
class SharedPreferencesScanHistoryStore implements ScanHistoryStore {
  const SharedPreferencesScanHistoryStore();

  static const String _key = 'scan_stock_history_v1';

  /// Maximum number of records retained — the confirmed first-release cap.
  /// After the 51st successful scan, the oldest record is dropped.
  static const int maxRecords = 50;

  @override
  Future<List<PersistedScanRecord>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final records = <PersistedScanRecord>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final record = PersistedScanRecord.tryFromJson(entry);
        // A malformed individual entry (e.g. a future format change) is
        // skipped rather than discarding the whole list.
        if (record != null) records.add(record);
      }
      records.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      return records;
    } catch (error) {
      // A corrupt/unreadable stored history must not crash the screen; it's
      // no worse than there being no history at all.
      debugPrint('Failed to read scan history: $error');
      return const [];
    }
  }

  @override
  Future<void> append(PersistedScanRecord record) async {
    try {
      final existing = await read();

      // Guards only against the exact same successful-lookup event being
      // processed twice in a row (e.g. a duplicate completion callback) —
      // never against a legitimate repeat scan of the same code/item at a
      // different time, which always gets its own entry (see class doc).
      if (existing.isNotEmpty && _isSameEvent(existing.first, record)) {
        return;
      }

      final updated = [...existing, record]
        ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      final retained = updated.length > maxRecords
          ? updated.sublist(0, maxRecords)
          : updated;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(retained.map((r) => r.toJson()).toList()),
      );
    } catch (error) {
      // Best-effort: the caller's in-memory result/Recent Scan state is
      // already updated independently of this store; only history
      // persistence failed, and that must never hide a successful lookup.
      debugPrint('Failed to persist scan history: $error');
    }
  }

  static bool _isSameEvent(PersistedScanRecord a, PersistedScanRecord b) {
    return a.rawCode == b.rawCode &&
        a.scannedAt == b.scannedAt &&
        a.itemNo == b.itemNo &&
        a.description == b.description &&
        a.batchReference == b.batchReference;
  }
}
