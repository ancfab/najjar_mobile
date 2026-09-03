// Unit tests for PurchaseOrderLine: the purchase-orders row model behind the
// expected-restock-date stock check. Covers the canonical-key contract, the
// lenient optional fields, the strict item-number requirement, and every
// "no usable date" degradation path (absent key, null, empty, BC's
// 0001-01-01 sentinel, malformed strings).

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/purchase_order_line.dart';

void main() {
  Map<String, dynamic> row({
    Object? itemNo = 'ITEM-TEST-01',
    Object? expectedReceiptDate = '2026-10-15',
  }) => {
    'Document_No': 'PO-TEST-001',
    'Line_No': 10000,
    if (itemNo != null) 'No': itemNo,
    'Description': 'Test Fabric Item',
    'Quantity': 100,
    if (expectedReceiptDate != null)
      'Expected_Receipt_Date': expectedReceiptDate,
  };

  test('parses a complete canonical row', () {
    final line = PurchaseOrderLine.fromJson(row());

    expect(line.itemNo, 'ITEM-TEST-01');
    expect(line.documentNo, 'PO-TEST-001');
    expect(line.lineNo, 10000);
    expect(line.description, 'Test Fabric Item');
    expect(line.quantity, 100);
    expect(line.expectedReceiptDate, DateTime(2026, 10, 15));
  });

  test('a missing or blank item number throws FormatException', () {
    expect(
      () => PurchaseOrderLine.fromJson(row(itemNo: null)),
      throwsFormatException,
    );
    expect(
      () => PurchaseOrderLine.fromJson(row(itemNo: '   ')),
      throwsFormatException,
    );
    expect(
      () => PurchaseOrderLine.fromJson(row(itemNo: 42)),
      throwsFormatException,
    );
  });

  test('every non-usable receipt date degrades to null, never throws', () {
    for (final value in [
      null,
      '',
      '0001-01-01',
      '0001-01-01T00:00:00Z',
      'not-a-date',
      '15/10/2026',
      12345,
    ]) {
      final line = PurchaseOrderLine.fromJson(
        row(expectedReceiptDate: value),
      );
      expect(line.expectedReceiptDate, isNull, reason: 'value: $value');
    }
  });

  test('a full ISO timestamp is truncated to its date', () {
    final line = PurchaseOrderLine.fromJson(
      row(expectedReceiptDate: '2026-10-15T00:00:00Z'),
    );
    expect(line.expectedReceiptDate, DateTime(2026, 10, 15));
  });

  test('optional fields tolerate absence and wrong types', () {
    final line = PurchaseOrderLine.fromJson(const {'No': 'ITEM-TEST-01'});

    expect(line.itemNo, 'ITEM-TEST-01');
    expect(line.documentNo, isNull);
    expect(line.lineNo, isNull);
    expect(line.description, isNull);
    expect(line.quantity, isNull);
    expect(line.expectedReceiptDate, isNull);
  });

  test('toString exposes only identity fields', () {
    final line = PurchaseOrderLine.fromJson(row());

    expect(line.toString(), isNot(contains('ITEM-TEST-01')));
    expect(line.toString(), isNot(contains('Test Fabric')));
    expect(line.toString(), contains('PO-TEST-001'));
  });
}
