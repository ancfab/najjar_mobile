// Unit tests for BusinessCentralItemSearchGroup/BusinessCentralItemVariation:
// the grouped `/items?search=...` response shape, distinct from the flat
// BusinessCentralItem contract. Covers required identity fields
// (commonItemNo/id/itemNo), optional variation fields, zero/negative
// totalInventory, and malformed-payload safety (FormatException, never an
// uncontrolled cast error).

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/business_central_item_search_group.dart';

Map<String, dynamic> _variationJson({
  String id = 'id-1012a01',
  String itemNo = '1012A01',
  String? commonItemNo = '1012',
  String? description = 'Cotton Sateen',
  String? baseUnitOfMeasure = 'YRD',
  Object? inventory = 210.5,
}) => {
  'id': id,
  'itemNo': itemNo,
  'commonItemNo': ?commonItemNo,
  'description': ?description,
  'baseUnitOfMeasure': ?baseUnitOfMeasure,
  'inventory': ?inventory,
};

Map<String, dynamic> _groupJson({
  String commonItemNo = '1012',
  Object totalInventory = 2523.9,
  List<Map<String, dynamic>>? variations,
}) => {
  'commonItemNo': commonItemNo,
  'totalInventory': totalInventory,
  'variations': variations ?? [_variationJson()],
};

void main() {
  group('BusinessCentralItemVariation.fromJson', () {
    test('parses every field when present', () {
      final variation = BusinessCentralItemVariation.fromJson(_variationJson());

      expect(variation.id, 'id-1012a01');
      expect(variation.itemNo, '1012A01');
      expect(variation.commonItemNo, '1012');
      expect(variation.description, 'Cotton Sateen');
      expect(variation.baseUnitOfMeasure, 'YRD');
      expect(variation.inventory, 210.5);
    });

    test('parses an integer inventory as a double', () {
      final variation = BusinessCentralItemVariation.fromJson(
        _variationJson(inventory: 210),
      );
      expect(variation.inventory, 210.0);
    });

    test('optional fields default to null when absent, never a fabricated '
        'value', () {
      final variation = BusinessCentralItemVariation.fromJson({
        'id': 'id-1',
        'itemNo': 'ITEM-1',
      });

      expect(variation.commonItemNo, isNull);
      expect(variation.description, isNull);
      expect(variation.baseUnitOfMeasure, isNull);
      expect(variation.inventory, isNull);
    });

    test('throws FormatException when id is missing', () {
      final json = _variationJson()..remove('id');
      expect(
        () => BusinessCentralItemVariation.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when id is empty', () {
      expect(
        () => BusinessCentralItemVariation.fromJson(_variationJson(id: '')),
        throwsFormatException,
      );
    });

    test('throws FormatException when itemNo is missing', () {
      final json = _variationJson()..remove('itemNo');
      expect(
        () => BusinessCentralItemVariation.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when itemNo is empty', () {
      expect(
        () => BusinessCentralItemVariation.fromJson(_variationJson(itemNo: '')),
        throwsFormatException,
      );
    });

    test('throws FormatException when an optional field has the wrong type '
        'rather than silently coercing it', () {
      final json = _variationJson()..['description'] = 42;
      expect(
        () => BusinessCentralItemVariation.fromJson(json),
        throwsFormatException,
      );
    });
  });

  group('BusinessCentralItemSearchGroup.fromJson', () {
    test('parses commonItemNo, totalInventory, and every variation', () {
      final group = BusinessCentralItemSearchGroup.fromJson(
        _groupJson(
          variations: [
            _variationJson(id: 'id-1', itemNo: '1012A01'),
            _variationJson(id: 'id-2', itemNo: '1012A02'),
          ],
        ),
      );

      expect(group.commonItemNo, '1012');
      expect(group.totalInventory, 2523.9);
      expect(group.variations, hasLength(2));
      expect(group.variations.map((v) => v.itemNo), ['1012A01', '1012A02']);
    });

    test('parses an integer totalInventory as a double', () {
      final group = BusinessCentralItemSearchGroup.fromJson(
        _groupJson(totalInventory: 2524),
      );
      expect(group.totalInventory, 2524.0);
    });

    test('zero totalInventory is preserved, never rejected', () {
      final group = BusinessCentralItemSearchGroup.fromJson(
        _groupJson(totalInventory: 0),
      );
      expect(group.totalInventory, 0.0);
    });

    test('a negative totalInventory is carried through as-is, never '
        'rejected or clamped', () {
      final group = BusinessCentralItemSearchGroup.fromJson(
        _groupJson(totalInventory: -12.5),
      );
      expect(group.totalInventory, -12.5);
    });

    test('an empty variations list is accepted', () {
      final group = BusinessCentralItemSearchGroup.fromJson(
        _groupJson(variations: []),
      );
      expect(group.variations, isEmpty);
    });

    test('throws FormatException when commonItemNo is missing', () {
      final json = _groupJson()..remove('commonItemNo');
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when commonItemNo is empty', () {
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(
          _groupJson(commonItemNo: ''),
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException when totalInventory is missing', () {
      final json = _groupJson()..remove('totalInventory');
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when totalInventory is not a number', () {
      final json = _groupJson()..['totalInventory'] = 'a lot';
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when variations is missing', () {
      final json = _groupJson()..remove('variations');
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when variations is not a JSON array', () {
      final json = _groupJson()..['variations'] = 'not-a-list';
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when a variations row is not a JSON '
        'object', () {
      final json = _groupJson()
        ..['variations'] = <Object?>[
          ..._groupJson()['variations'] as List,
          'not-an-object',
        ];
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(json),
        throwsFormatException,
      );
    });

    test('throws FormatException when a nested variation is malformed '
        '(propagates rather than silently dropping the row)', () {
      final json = _groupJson(
        variations: [
          _variationJson(),
          _variationJson(id: ''),
        ],
      );
      expect(
        () => BusinessCentralItemSearchGroup.fromJson(json),
        throwsFormatException,
      );
    });
  });
}
