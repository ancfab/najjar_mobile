// Unit tests for SharedPreferencesScanHistoryStore: the newest-first,
// 50-record-capped local persistence backing the Scan History screen.
// Uses SharedPreferences.setMockInitialValues rather than a real platform
// channel, matching last_scan_store_test.dart's convention.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/services/last_scan_store.dart';
import 'package:anc_fabrics/services/scan_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PersistedScanRecord record({
    required String rawCode,
    required DateTime scannedAt,
    String? itemNo,
    String? description,
    String? batchReference,
  }) => PersistedScanRecord(
    rawCode: rawCode,
    scannedAt: scannedAt,
    itemNo: itemNo,
    description: description,
    batchReference: batchReference,
  );

  group('SharedPreferencesScanHistoryStore', () {
    test('empty history returns an empty list', () async {
      const store = SharedPreferencesScanHistoryStore();

      expect(await store.read(), isEmpty);
    });

    test('one successful record round-trips correctly', () async {
      const store = SharedPreferencesScanHistoryStore();
      await store.append(
        record(
          rawCode: 'ITEM-0042',
          scannedAt: DateTime.utc(2026, 7, 31, 12, 30),
          itemNo: 'ITEM-0042',
          description: 'Egyptian Cotton Sateen',
          batchReference: 'BATCH-9',
        ),
      );

      final records = await store.read();

      expect(records, hasLength(1));
      expect(records.single.rawCode, 'ITEM-0042');
      expect(records.single.scannedAt, DateTime.utc(2026, 7, 31, 12, 30));
      expect(records.single.itemNo, 'ITEM-0042');
      expect(records.single.description, 'Egyptian Cotton Sateen');
      expect(records.single.batchReference, 'BATCH-9');
    });

    test('multiple records round-trip correctly', () async {
      const store = SharedPreferencesScanHistoryStore();
      await store.append(
        record(rawCode: 'A', scannedAt: DateTime.utc(2026, 1, 1)),
      );
      await store.append(
        record(rawCode: 'B', scannedAt: DateTime.utc(2026, 1, 2)),
      );
      await store.append(
        record(rawCode: 'C', scannedAt: DateTime.utc(2026, 1, 3)),
      );

      final records = await store.read();

      expect(records, hasLength(3));
      expect(records.map((r) => r.rawCode), containsAll(['A', 'B', 'C']));
    });

    test('records are returned newest first', () async {
      const store = SharedPreferencesScanHistoryStore();
      await store.append(
        record(rawCode: 'OLDEST', scannedAt: DateTime.utc(2026, 1, 1)),
      );
      await store.append(
        record(rawCode: 'MIDDLE', scannedAt: DateTime.utc(2026, 1, 2)),
      );
      await store.append(
        record(rawCode: 'NEWEST', scannedAt: DateTime.utc(2026, 1, 3)),
      );

      final records = await store.read();

      expect(records.map((r) => r.rawCode).toList(), [
        'NEWEST',
        'MIDDLE',
        'OLDEST',
      ]);
    });

    test('internal spaces and exact raw codes are preserved', () async {
      const store = SharedPreferencesScanHistoryStore();
      await store.append(
        record(rawCode: '1038 01', scannedAt: DateTime.utc(2026, 1, 1)),
      );

      final records = await store.read();

      expect(records.single.rawCode, '1038 01');
    });

    test('null optional fields round-trip safely', () async {
      const store = SharedPreferencesScanHistoryStore();
      await store.append(
        record(rawCode: 'RAW-ONLY', scannedAt: DateTime.utc(2026, 1, 1)),
      );

      final records = await store.read();

      expect(records.single.itemNo, isNull);
      expect(records.single.description, isNull);
      expect(records.single.batchReference, isNull);
    });

    test('blank optional fields are treated safely', () async {
      const store = SharedPreferencesScanHistoryStore();
      await store.append(
        record(
          rawCode: 'BLANK-FIELDS',
          scannedAt: DateTime.utc(2026, 1, 1),
          itemNo: '',
          description: '',
          batchReference: '',
        ),
      );

      final records = await store.read();

      expect(records, hasLength(1));
      expect(records.single.itemNo, '');
      expect(records.single.description, '');
      expect(records.single.batchReference, '');
    });

    test('quantity/location/unit are not serialized', () async {
      const store = SharedPreferencesScanHistoryStore();
      final saved = record(
        rawCode: 'ITEM-1',
        scannedAt: DateTime.utc(2026, 1, 1),
      );
      await store.append(saved);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('scan_stock_history_v1')!;

      expect(raw, isNot(contains('quantity')));
      expect(raw, isNot(contains('remainingQuantity')));
      expect(raw, isNot(contains('location')));
      expect(raw, isNot(contains('unitOfMeasure')));
      expect(saved.toJson().keys, [
        'rawCode',
        'scannedAt',
        'itemNo',
        'description',
        'batchReference',
      ]);
    });

    test('a maximum of 50 records are retained', () async {
      const store = SharedPreferencesScanHistoryStore();
      for (var i = 0; i < 50; i++) {
        await store.append(
          record(
            rawCode: 'ITEM-$i',
            scannedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }

      final records = await store.read();

      expect(records, hasLength(50));
    });

    test('the 51st record removes the oldest', () async {
      const store = SharedPreferencesScanHistoryStore();
      for (var i = 0; i < 51; i++) {
        await store.append(
          record(
            rawCode: 'ITEM-$i',
            scannedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }

      final records = await store.read();

      expect(records, hasLength(50));
      expect(records.map((r) => r.rawCode), isNot(contains('ITEM-0')));
      expect(records.map((r) => r.rawCode), contains('ITEM-50'));
      expect(records.map((r) => r.rawCode), contains('ITEM-1'));
    });

    test('repeated scans of the same code at different timestamps remain '
        'separate', () async {
      const store = SharedPreferencesScanHistoryStore();
      await store.append(
        record(rawCode: 'SAME-ITEM', scannedAt: DateTime.utc(2026, 1, 1)),
      );
      await store.append(
        record(rawCode: 'SAME-ITEM', scannedAt: DateTime.utc(2026, 1, 2)),
      );

      final records = await store.read();

      expect(records, hasLength(2));
    });

    test(
      'the exact same event appended twice in a row is not duplicated',
      () async {
        const store = SharedPreferencesScanHistoryStore();
        final duplicate = record(
          rawCode: 'SAME-EVENT',
          scannedAt: DateTime.utc(2026, 1, 1),
          itemNo: 'ITEM-1',
          description: 'Cotton',
          batchReference: 'B-1',
        );
        await store.append(duplicate);
        await store.append(duplicate);

        final records = await store.read();

        expect(records, hasLength(1));
      },
    );

    test('malformed stored JSON produces an empty/safe result', () async {
      SharedPreferences.setMockInitialValues({
        'scan_stock_history_v1': 'not valid json',
      });
      const store = SharedPreferencesScanHistoryStore();

      expect(await store.read(), isEmpty);
    });

    test(
      'a stored JSON value that is not a list is treated as empty',
      () async {
        SharedPreferences.setMockInitialValues({
          'scan_stock_history_v1': '{"rawCode": "not-a-list"}',
        });
        const store = SharedPreferencesScanHistoryStore();

        expect(await store.read(), isEmpty);
      },
    );

    test('invalid individual records are skipped safely', () async {
      SharedPreferences.setMockInitialValues({
        'scan_stock_history_v1':
            '[{"rawCode": "VALID", "scannedAt": "2026-01-01T00:00:00.000Z"}, '
            '{"scannedAt": "2026-01-02T00:00:00.000Z"}, '
            '"not-even-a-map"]',
      });
      const store = SharedPreferencesScanHistoryStore();

      final records = await store.read();

      expect(records, hasLength(1));
      expect(records.single.rawCode, 'VALID');
    });

    test(
      'a completely unusable stored value is treated as empty history',
      () async {
        SharedPreferences.setMockInitialValues({
          'scan_stock_history_v1': '[1, 2, 3',
        });
        const store = SharedPreferencesScanHistoryStore();

        expect(await store.read(), isEmpty);
      },
    );
  });
}
