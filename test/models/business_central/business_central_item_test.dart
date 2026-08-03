// Unit tests for BusinessCentralItem.fromJson: exact camelCase key parsing
// against the confirmed live items contract, safe int-or-double
// inventory/unitPrice parsing, empty-string-allowed optional fields,
// undocumented/OData field tolerance, malformed/missing-field rejection
// with no silent fallback values, and toString() safety.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/business_central_item.dart';

Map<String, dynamic> _validJson({
  Object? inventory = 993,
  Object? unitPrice = 12.5,
}) => {
  '@odata.etag':
      'W/"JzQ0O1JSRE...'
      'ImageValue=="\'',
  'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
  'itemNo': 'ITEM-001',
  'commonItemNo': 'COMMON-001',
  'description': 'Egyptian Cotton Sateen (600TC)',
  'description2': '',
  'baseUnitOfMeasure': 'YRD',
  'itemCategoryCode': 'FABRIC',
  'productGroupCode': 'COTTON',
  'blocked': false,
  'inventory': inventory,
  'unitPrice': unitPrice,
  'gtin': '',
  'Global_Dimension_1_Filter': '',
  'Global_Dimension_2_Filter': '',
  'Location_Filter': '',
  'Drop_Shipment_Filter': '',
  'Variant_Filter': '',
  'Lot_No_Filter': '',
  'Serial_No_Filter': '',
  'Unit_of_Measure_Filter': '',
  'Package_No_Filter': '',
};

void main() {
  group('BusinessCentralItem.fromJson', () {
    test(
      'parses all exact camelCase keys from the confirmed live contract',
      () {
        final item = BusinessCentralItem.fromJson(_validJson());

        expect(item.id, 'd472efc4-9f2b-4a1a-9e7a-1234567890ab');
        expect(item.itemNo, 'ITEM-001');
        expect(item.commonItemNo, 'COMMON-001');
        expect(item.description, 'Egyptian Cotton Sateen (600TC)');
        expect(item.description2, '');
        expect(item.baseUnitOfMeasure, 'YRD');
        expect(item.itemCategoryCode, 'FABRIC');
        expect(item.productGroupCode, 'COTTON');
        expect(item.blocked, isFalse);
        expect(item.inventory, 993.0);
        expect(item.unitPrice, 12.5);
        expect(item.gtin, '');
      },
    );

    test('parses an integer inventory as a double', () {
      final item = BusinessCentralItem.fromJson(_validJson(inventory: 993));
      expect(item.inventory, 993.0);
      expect(item.inventory, isA<double>());
    });

    test('parses a decimal inventory as a double', () {
      final item = BusinessCentralItem.fromJson(_validJson(inventory: 703.8));
      expect(item.inventory, 703.8);
    });

    test('parses an integer unitPrice as a double', () {
      final item = BusinessCentralItem.fromJson(_validJson(unitPrice: 100));
      expect(item.unitPrice, 100.0);
      expect(item.unitPrice, isA<double>());
    });

    test('parses a decimal unitPrice', () {
      final item = BusinessCentralItem.fromJson(_validJson(unitPrice: 850.75));
      expect(item.unitPrice, 850.75);
    });

    test('parses blocked as a Boolean, true and false', () {
      final blockedJson = _validJson();
      blockedJson['blocked'] = true;
      expect(BusinessCentralItem.fromJson(blockedJson).blocked, isTrue);

      final unblockedJson = _validJson();
      unblockedJson['blocked'] = false;
      expect(BusinessCentralItem.fromJson(unblockedJson).blocked, isFalse);
    });

    test('accepts empty description2/itemCategoryCode/productGroupCode/gtin '
        '(the confirmed live contract allows these to be empty strings)', () {
      for (final key in [
        'description2',
        'itemCategoryCode',
        'productGroupCode',
        'gtin',
      ]) {
        final json = _validJson();
        json[key] = '';
        final item = BusinessCentralItem.fromJson(json);
        expect(
          switch (key) {
            'description2' => item.description2,
            'itemCategoryCode' => item.itemCategoryCode,
            'productGroupCode' => item.productGroupCode,
            'gtin' => item.gtin,
            _ => throw StateError('unreachable'),
          },
          '',
          reason: 'An empty "$key" must be passed through unmodified.',
        );
      }
    });

    test('ignores undocumented/OData/internal filter fields', () {
      final item = BusinessCentralItem.fromJson(_validJson());
      // No exception thrown and no such data retained anywhere on the model
      // (there are no fields to hold them) — parsing simply succeeds.
      expect(item.id, isNotEmpty);
    });

    test('parses successfully even when @odata.etag is absent', () {
      final json = _validJson()..remove('@odata.etag');
      expect(() => BusinessCentralItem.fromJson(json), returnsNormally);
    });

    for (final requiredKey in [
      'id',
      'itemNo',
      'commonItemNo',
      'description',
      'description2',
      'baseUnitOfMeasure',
      'itemCategoryCode',
      'productGroupCode',
      'blocked',
      'inventory',
      'unitPrice',
      'gtin',
    ]) {
      test('rejects a missing $requiredKey', () {
        final json = _validJson()..remove(requiredKey);
        expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
      });
    }

    test('rejects a non-string id', () {
      final json = _validJson();
      json['id'] = 12345;
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects a non-string itemNo', () {
      final json = _validJson();
      json['itemNo'] = 12345;
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test(
      'rejects an empty id — an accepted empty id would let two distinct '
      'rows silently collapse under the same "" dedup key in ItemsService',
      () {
        final json = _validJson();
        json['id'] = '';
        expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
      },
    );

    test('rejects an empty itemNo — the primary Business Central display/'
        'business identifier must always identify a real item', () {
      final json = _validJson();
      json['itemNo'] = '';
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects a non-bool blocked', () {
      final json = _validJson();
      json['blocked'] = 'false';
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects a non-numeric inventory', () {
      final json = _validJson();
      json['inventory'] = 'not-a-number';
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects a non-numeric unitPrice', () {
      final json = _validJson();
      json['unitPrice'] = 'not-a-number';
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects a null inventory', () {
      final json = _validJson();
      json['inventory'] = null;
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects a null unitPrice', () {
      final json = _validJson();
      json['unitPrice'] = null;
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects lower_snake_case field names (does not accept item_no as '
        'an alias for itemNo)', () {
      final json = {
        'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
        'item_no': 'ITEM-001',
        'common_item_no': 'COMMON-001',
        'description': 'Egyptian Cotton Sateen (600TC)',
        'description2': '',
        'base_unit_of_measure': 'YRD',
        'item_category_code': 'FABRIC',
        'product_group_code': 'COTTON',
        'blocked': false,
        'inventory': 993,
        'unit_price': 12.5,
        'gtin': '',
      };
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('rejects PascalCase_With_Underscores field names (does not accept '
        'Item_No as an alias for itemNo)', () {
      final json = {
        'id': 'd472efc4-9f2b-4a1a-9e7a-1234567890ab',
        'Item_No': 'ITEM-001',
        'Common_Item_No': 'COMMON-001',
        'Description': 'Egyptian Cotton Sateen (600TC)',
        'Description_2': '',
        'Base_Unit_of_Measure': 'YRD',
        'Item_Category_Code': 'FABRIC',
        'Product_Group_Code': 'COTTON',
        'Blocked': false,
        'Inventory': 993,
        'Unit_Price': 12.5,
        'GTIN': '',
      };
      expect(() => BusinessCentralItem.fromJson(json), throwsFormatException);
    });

    test('does not expose unitPrice/inventory in toString', () {
      final item = BusinessCentralItem.fromJson(
        _validJson(inventory: 993, unitPrice: 12.5),
      );
      final text = item.toString();

      expect(text, isNot(contains('993')));
      expect(text, isNot(contains('12.5')));
      expect(text, contains('ITEM-001'));
      expect(text, contains('d472efc4-9f2b-4a1a-9e7a-1234567890ab'));
    });
  });
}
