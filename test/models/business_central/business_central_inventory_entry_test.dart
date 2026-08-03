// Unit tests for BusinessCentralInventoryEntry.fromJson: exact camelCase
// key parsing against the documented inventory contract, safe int-or-double
// quantity/remainingQuantity parsing, empty-string-allowed undocumented
// fields, unknown-field tolerance, malformed/missing-field rejection with
// no silent fallback values, and wrong-casing alias rejection.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/business_central_inventory_entry.dart';

Map<String, dynamic> _validJson({
  Object? quantity = 100,
  Object? remainingQuantity = 40,
}) => {
  'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
  'entryNo': 1001,
  'postingDate': '2026-01-05',
  'documentType': 'Purchase',
  'documentNo': 'PO-1001',
  'itemNo': 'ITEM-001',
  'description': 'Egyptian Cotton Sateen (600TC)',
  'locationCode': 'MAIN',
  'quantity': quantity,
  'remainingQuantity': remainingQuantity,
  'unitOfMeasureCode': 'YRD',
  'open': true,
};

void main() {
  group('BusinessCentralInventoryEntry.fromJson', () {
    test('parses all documented camelCase fields', () {
      final entry = BusinessCentralInventoryEntry.fromJson(_validJson());

      expect(entry.id, 'd472efc4-9f2b-4a1a-9e7a-1234567890ab');
      expect(entry.entryNo, 1001);
      expect(entry.postingDate, '2026-01-05');
      expect(entry.documentType, 'Purchase');
      expect(entry.documentNo, 'PO-1001');
      expect(entry.itemNo, 'ITEM-001');
      expect(entry.description, 'Egyptian Cotton Sateen (600TC)');
      expect(entry.locationCode, 'MAIN');
      expect(entry.quantity, 100.0);
      expect(entry.remainingQuantity, 40.0);
      expect(entry.unitOfMeasureCode, 'YRD');
      expect(entry.open, isTrue);
    });

    test('parses an integer quantity as a double', () {
      final entry = BusinessCentralInventoryEntry.fromJson(
        _validJson(quantity: 100),
      );
      expect(entry.quantity, 100.0);
      expect(entry.quantity, isA<double>());
    });

    test('parses a decimal quantity as a double', () {
      final entry = BusinessCentralInventoryEntry.fromJson(
        _validJson(quantity: 100.75),
      );
      expect(entry.quantity, 100.75);
    });

    test('parses an integer remainingQuantity as a double', () {
      final entry = BusinessCentralInventoryEntry.fromJson(
        _validJson(remainingQuantity: 40),
      );
      expect(entry.remainingQuantity, 40.0);
      expect(entry.remainingQuantity, isA<double>());
    });

    test('parses a decimal remainingQuantity as a double', () {
      final entry = BusinessCentralInventoryEntry.fromJson(
        _validJson(remainingQuantity: 39.5),
      );
      expect(entry.remainingQuantity, 39.5);
    });

    test('parses open true', () {
      final json = _validJson();
      json['open'] = true;
      expect(BusinessCentralInventoryEntry.fromJson(json).open, isTrue);
    });

    test('parses open false', () {
      final json = _validJson();
      json['open'] = false;
      expect(BusinessCentralInventoryEntry.fromJson(json).open, isFalse);
    });

    test('ignores unknown fields', () {
      final json = {
        ..._validJson(),
        '@odata.etag': 'W/"JzQ0O1234567890abcdef;1234567\'"',
        'Vendor_No': 'VEND-001',
        'Unit_Cost_LCY': 612.5,
        'someUndocumentedField': 'anything',
      };
      final entry = BusinessCentralInventoryEntry.fromJson(json);
      expect(entry.id, isNotEmpty);
      expect(entry.itemNo, 'ITEM-001');
    });

    test('accepts empty strings for fields without a documented non-empty '
        'rule (documentType/documentNo/description/locationCode/'
        'unitOfMeasureCode/postingDate)', () {
      for (final key in [
        'documentType',
        'documentNo',
        'description',
        'locationCode',
        'unitOfMeasureCode',
        'postingDate',
      ]) {
        final json = _validJson();
        json[key] = '';
        final entry = BusinessCentralInventoryEntry.fromJson(json);
        expect(
          switch (key) {
            'documentType' => entry.documentType,
            'documentNo' => entry.documentNo,
            'description' => entry.description,
            'locationCode' => entry.locationCode,
            'unitOfMeasureCode' => entry.unitOfMeasureCode,
            'postingDate' => entry.postingDate,
            _ => throw StateError('unreachable'),
          },
          '',
          reason: 'An empty "$key" must be passed through unmodified.',
        );
      }
    });

    test('rejects an empty id — the documented pagination dedup identity', () {
      final json = _validJson();
      json['id'] = '';
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects an empty itemNo — the Business Central item identifier', () {
      final json = _validJson();
      json['itemNo'] = '';
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    for (final requiredKey in [
      'id',
      'entryNo',
      'postingDate',
      'documentType',
      'documentNo',
      'itemNo',
      'description',
      'locationCode',
      'quantity',
      'remainingQuantity',
      'unitOfMeasureCode',
      'open',
    ]) {
      test('rejects a missing $requiredKey', () {
        final json = _validJson()..remove(requiredKey);
        expect(
          () => BusinessCentralInventoryEntry.fromJson(json),
          throwsFormatException,
        );
      });
    }

    test('rejects a non-string id', () {
      final json = _validJson();
      json['id'] = 12345;
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-string itemNo', () {
      final json = _validJson();
      json['itemNo'] = 12345;
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-int entryNo', () {
      final json = _validJson();
      json['entryNo'] = '1001';
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a decimal entryNo (strict int convention)', () {
      final json = _validJson();
      json['entryNo'] = 1001.5;
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-bool open', () {
      final json = _validJson();
      json['open'] = 'true';
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-numeric quantity', () {
      final json = _validJson();
      json['quantity'] = 'not-a-number';
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-numeric remainingQuantity', () {
      final json = _validJson();
      json['remainingQuantity'] = 'not-a-number';
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a null quantity', () {
      final json = _validJson();
      json['quantity'] = null;
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a null remainingQuantity', () {
      final json = _validJson();
      json['remainingQuantity'] = null;
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects a non-string postingDate', () {
      final json = _validJson();
      json['postingDate'] = 20260105;
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects lower_snake_case field names (does not accept item_no as '
        'an alias for itemNo)', () {
      final json = {
        'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
        'entry_no': 1001,
        'posting_date': '2026-01-05',
        'document_type': 'Purchase',
        'document_no': 'PO-1001',
        'item_no': 'ITEM-001',
        'description': 'Egyptian Cotton Sateen (600TC)',
        'location_code': 'MAIN',
        'quantity': 100,
        'remaining_quantity': 40,
        'unit_of_measure_code': 'YRD',
        'open': true,
      };
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects PascalCase_With_Underscores field names (does not accept '
        'Item_No as an alias for itemNo)', () {
      final json = {
        'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
        'Entry_No': 1001,
        'Posting_Date': '2026-01-05',
        'Document_Type': 'Purchase',
        'Document_No': 'PO-1001',
        'Item_No': 'ITEM-001',
        'Description': 'Egyptian Cotton Sateen (600TC)',
        'Location_Code': 'MAIN',
        'Quantity': 100,
        'Remaining_Quantity': 40,
        'Unit_of_Measure_Code': 'YRD',
        'Open': true,
      };
      expect(
        () => BusinessCentralInventoryEntry.fromJson(json),
        throwsFormatException,
      );
    });
  });
}
