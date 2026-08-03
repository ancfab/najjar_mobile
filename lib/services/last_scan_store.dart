import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Purpose: The non-sensitive display fields of the single most recent
/// successful Scan Stock lookup, persisted locally so the Recent Scan
/// section survives reopening [ScanStockScreen].
///
/// Deliberately narrower than [StockLookupSuccess]: quantity/location/unit
/// are not part of the Recent Scan summary (see [ScanStockScreen]'s Recent
/// Scan card), so they are not persisted here either — this is a display
/// record, not a cache of the full lookup response.
class PersistedScanRecord {
  const PersistedScanRecord({
    required this.rawCode,
    required this.scannedAt,
    this.itemNo,
    this.description,
    this.batchReference,
  });

  final String rawCode;
  final DateTime scannedAt;
  final String? itemNo;
  final String? description;
  final String? batchReference;

  Map<String, dynamic> toJson() => {
    'rawCode': rawCode,
    'scannedAt': scannedAt.toIso8601String(),
    'itemNo': itemNo,
    'description': description,
    'batchReference': batchReference,
  };

  /// Returns `null` for JSON that doesn't match the current shape (e.g. a
  /// future format change) rather than throwing — a corrupt/unreadable
  /// persisted record should fall back to "no recent scan", not crash the
  /// screen.
  static PersistedScanRecord? tryFromJson(Map<String, dynamic> json) {
    final rawCode = json['rawCode'];
    final scannedAtRaw = json['scannedAt'];
    if (rawCode is! String || rawCode.isEmpty) return null;
    if (scannedAtRaw is! String) return null;
    final scannedAt = DateTime.tryParse(scannedAtRaw);
    if (scannedAt == null) return null;

    return PersistedScanRecord(
      rawCode: rawCode,
      scannedAt: scannedAt,
      itemNo: json['itemNo'] is String ? json['itemNo'] as String : null,
      description: json['description'] is String
          ? json['description'] as String
          : null,
      batchReference: json['batchReference'] is String
          ? json['batchReference'] as String
          : null,
    );
  }
}

/// Persistence seam for the single last successful scan, isolated behind
/// this abstraction so [ScanStockScreen] (and its widget tests) don't
/// depend on the `shared_preferences` platform channel directly.
///
/// Intentionally a single-record store, not a history collection — see the
/// Scan Stock frontend task's scope notes on why a full scan history is out
/// of scope here.
abstract class LastScanStore {
  /// The most recently saved record, or `null` if none has been saved yet
  /// (or the stored value could not be read back).
  Future<PersistedScanRecord?> read();

  /// Overwrites the single stored record with [record].
  Future<void> save(PersistedScanRecord record);
}

/// Default [LastScanStore], backed by `shared_preferences` — appropriate
/// here since a scan result's display fields are not sensitive, matching
/// `SessionStorageKeys`'s existing plain-SharedPreferences precedent for
/// non-sensitive local state (as opposed to `SecureAuthSessionStore`).
class SharedPreferencesLastScanStore implements LastScanStore {
  const SharedPreferencesLastScanStore();

  static const String _key = 'scan_stock_last_scan_v1';

  @override
  Future<PersistedScanRecord?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PersistedScanRecord.tryFromJson(decoded);
    } catch (error) {
      // A corrupt/unreadable stored record must not crash the screen; it's
      // no worse than there being no recent scan at all.
      debugPrint('Failed to read last scan record: $error');
      return null;
    }
  }

  @override
  Future<void> save(PersistedScanRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(record.toJson()));
    } catch (error) {
      // Best-effort: the in-memory Recent Scan state is already updated by
      // the caller: only cross-restart persistence failed.
      debugPrint('Failed to persist last scan record: $error');
    }
  }
}
