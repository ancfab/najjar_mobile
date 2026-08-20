// Unit tests for the StockLookupService contract's only production
// implementation, UnconfiguredStockLookupService: it must always return a
// controlled StockLookupMappingNotConfigured result (never throw, never
// return fake stock data) since the scan/manual code identity and the
// backend-side lookup contract are unresolved.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/stock_lookup_service.dart';

void main() {
  group('UnconfiguredStockLookupService', () {
    test(
      'returns StockLookupMappingNotConfigured carrying the raw code',
      () async {
        const service = UnconfiguredStockLookupService();

        final result = await service.lookup('ITEM-0042');

        expect(result, isA<StockLookupMappingNotConfigured>());
        expect(result.rawCode, 'ITEM-0042');
      },
    );

    test('never returns success or fake stock data', () async {
      const service = UnconfiguredStockLookupService();

      final result = await service.lookup('012345678905');

      expect(result, isNot(isA<StockLookupSuccess>()));
    });

    test('is stable across repeated calls with different codes', () async {
      const service = UnconfiguredStockLookupService();

      final first = await service.lookup('CODE-A');
      final second = await service.lookup('CODE-B');

      expect(first.rawCode, 'CODE-A');
      expect(second.rawCode, 'CODE-B');
      expect(first, isA<StockLookupMappingNotConfigured>());
      expect(second, isA<StockLookupMappingNotConfigured>());
    });
  });

  group('StockLookupSuccess', () {
    test('carries only the fields explicitly provided, nulling the rest', () {
      final result = StockLookupSuccess(
        'ITEM-0042',
        scannedAt: DateTime(2026, 1, 1),
        itemNo: 'ITEM-0042',
        description: 'Egyptian Cotton Sateen',
      );

      expect(result.itemNo, 'ITEM-0042');
      expect(result.description, 'Egyptian Cotton Sateen');
      expect(result.batchReference, isNull);
      expect(result.availabilityByLocation, isEmpty);
    });

    test('carries the given per-location availability list unchanged', () {
      final result = StockLookupSuccess(
        '1038 01',
        scannedAt: DateTime(2026, 1, 1),
        itemNo: '1038 01',
        availabilityByLocation: const [
          StockLocationAvailability(
            locationCode: 'BEIRUT',
            remainingQuantity: 80,
            unitOfMeasureCode: 'MT',
          ),
          StockLocationAvailability(
            locationCode: 'TRIPOLI',
            remainingQuantity: 20,
            unitOfMeasureCode: 'MT',
          ),
        ],
      );

      expect(result.availabilityByLocation, hasLength(2));
      expect(result.availabilityByLocation.first.locationCode, 'BEIRUT');
      expect(result.availabilityByLocation.first.remainingQuantity, 80);
    });
  });

  group('StockLocationAvailability', () {
    test('two instances with the same fields compare equal', () {
      const a = StockLocationAvailability(
        locationCode: 'BEIRUT',
        remainingQuantity: 80,
        unitOfMeasureCode: 'MT',
      );
      const b = StockLocationAvailability(
        locationCode: 'BEIRUT',
        remainingQuantity: 80,
        unitOfMeasureCode: 'MT',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different locationCode, quantity, or unit is not equal', () {
      const base = StockLocationAvailability(
        locationCode: 'BEIRUT',
        remainingQuantity: 80,
        unitOfMeasureCode: 'MT',
      );

      expect(
        base,
        isNot(
          const StockLocationAvailability(
            locationCode: 'TRIPOLI',
            remainingQuantity: 80,
            unitOfMeasureCode: 'MT',
          ),
        ),
      );
      expect(
        base,
        isNot(
          const StockLocationAvailability(
            locationCode: 'BEIRUT',
            remainingQuantity: 20,
            unitOfMeasureCode: 'MT',
          ),
        ),
      );
      expect(
        base,
        isNot(
          const StockLocationAvailability(
            locationCode: 'BEIRUT',
            remainingQuantity: 80,
            unitOfMeasureCode: 'PCS',
          ),
        ),
      );
    });

    group('isLowStockInMeters', () {
      test('99 m (below the 100 m threshold) is low stock', () {
        const availability = StockLocationAvailability(
          locationCode: 'BEIRUT',
          remainingQuantity: 99,
          unitOfMeasureCode: 'MT',
        );

        expect(availability.isLowStockInMeters, isTrue);
      });

      test('100 m (the boundary, inclusive) is low stock', () {
        const availability = StockLocationAvailability(
          locationCode: 'BEIRUT',
          remainingQuantity: 100,
          unitOfMeasureCode: 'MT',
        );

        expect(availability.isLowStockInMeters, isTrue);
      });

      test('100.01 m (just above the boundary) is not low stock', () {
        const availability = StockLocationAvailability(
          locationCode: 'BEIRUT',
          remainingQuantity: 100.01,
          unitOfMeasureCode: 'MT',
        );

        expect(availability.isLowStockInMeters, isFalse);
      });

      test('150 m is not low stock', () {
        const availability = StockLocationAvailability(
          locationCode: 'BEIRUT',
          remainingQuantity: 150,
          unitOfMeasureCode: 'MT',
        );

        expect(availability.isLowStockInMeters, isFalse);
      });

      test('a non-meters unit at or below 100 is never low stock — the rule '
          'is meters-specific', () {
        const availability = StockLocationAvailability(
          locationCode: 'BEIRUT',
          remainingQuantity: 15,
          unitOfMeasureCode: 'YD',
        );

        expect(availability.isLowStockInMeters, isFalse);
      });

      test('PCS at or below 100 is never low stock', () {
        const availability = StockLocationAvailability(
          locationCode: 'BEIRUT',
          remainingQuantity: 5,
          unitOfMeasureCode: 'PCS',
        );

        expect(availability.isLowStockInMeters, isFalse);
      });
    });
  });
}
