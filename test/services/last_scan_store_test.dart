// Unit tests for SharedPreferencesLastScanStore/PersistedScanRecord: the
// single-record local persistence backing Scan Stock's Recent Scan card.
// Uses SharedPreferences.setMockInitialValues rather than a real platform
// channel, matching the convention in secure_auth_session_store_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/services/last_scan_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SharedPreferencesLastScanStore', () {
    test('read returns null when nothing has been saved', () async {
      const store = SharedPreferencesLastScanStore();

      expect(await store.read(), isNull);
    });

    test('save then read round-trips every field', () async {
      const store = SharedPreferencesLastScanStore();
      final record = PersistedScanRecord(
        rawCode: 'ITEM-0042',
        scannedAt: DateTime.utc(2026, 7, 31, 12, 30),
        itemNo: 'ITEM-0042',
        description: 'Egyptian Cotton Sateen',
        batchReference: 'BATCH-9',
      );

      await store.save(record);
      final restored = await store.read();

      expect(restored, isNotNull);
      expect(restored!.rawCode, 'ITEM-0042');
      expect(restored.scannedAt, record.scannedAt);
      expect(restored.itemNo, 'ITEM-0042');
      expect(restored.description, 'Egyptian Cotton Sateen');
      expect(restored.batchReference, 'BATCH-9');
    });

    test(
      'save then read round-trips a record with only required fields',
      () async {
        const store = SharedPreferencesLastScanStore();
        final record = PersistedScanRecord(
          rawCode: 'RAW-ONLY',
          scannedAt: DateTime.utc(2026, 1, 1),
        );

        await store.save(record);
        final restored = await store.read();

        expect(restored!.rawCode, 'RAW-ONLY');
        expect(restored.itemNo, isNull);
        expect(restored.description, isNull);
        expect(restored.batchReference, isNull);
      },
    );

    test('a newer save overwrites the previously persisted record', () async {
      const store = SharedPreferencesLastScanStore();
      await store.save(
        PersistedScanRecord(
          rawCode: 'FIRST',
          scannedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await store.save(
        PersistedScanRecord(
          rawCode: 'SECOND',
          scannedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final restored = await store.read();

      expect(restored!.rawCode, 'SECOND');
    });

    test('malformed stored JSON is treated as no recent scan', () async {
      SharedPreferences.setMockInitialValues({
        'scan_stock_last_scan_v1': 'not valid json',
      });
      const store = SharedPreferencesLastScanStore();

      expect(await store.read(), isNull);
    });
  });

  group('PersistedScanRecord.tryFromJson', () {
    test('returns null when rawCode is missing', () {
      final result = PersistedScanRecord.tryFromJson({
        'scannedAt': DateTime.now().toIso8601String(),
      });

      expect(result, isNull);
    });

    test('returns null when scannedAt is not a parseable date', () {
      final result = PersistedScanRecord.tryFromJson({
        'rawCode': 'ITEM-1',
        'scannedAt': 'not-a-date',
      });

      expect(result, isNull);
    });
  });
}
