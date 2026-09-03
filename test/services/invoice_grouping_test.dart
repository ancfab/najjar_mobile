// Unit tests for selectLatestInvoiceLines: pure grouping/selection logic
// over already-fetched invoice lines, kept independent of any transport
// concern so it can be exercised without HTTP/session plumbing.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/business_central/business_central_invoice_line.dart';
import 'package:anc_fabrics/services/invoice_grouping.dart';

BusinessCentralInvoiceLine _line({
  required String documentNo,
  required int lineNo,
  String orderNo = 'SO-24001',
  DateTime? postingDate,
}) => BusinessCentralInvoiceLine(
  documentNo: documentNo,
  lineNo: lineNo,
  postingDate: postingDate,
  sellToCustomerNo: 'CLNT-0001',
  sellToCustomerName: 'Test Customer One',
  type: 'Item',
  itemNo: '880107',
  description: 'Test Fabric Item',
  quantity: 12,
  unitPrice: 15,
  amount: 180,
  amountIncludingVat: 189,
  orderNo: orderNo,
  currencyCode: 'AED',
);

void main() {
  group('selectLatestInvoiceLines', () {
    test('empty input returns null (no related invoice)', () {
      expect(selectLatestInvoiceLines(const []), isNull);
    });

    test('a single invoice returns all of its lines', () {
      final lines = [
        _line(documentNo: 'INV-24001', lineNo: 10000),
        _line(documentNo: 'INV-24001', lineNo: 20000),
      ];

      final selected = selectLatestInvoiceLines(lines);

      expect(selected, hasLength(2));
      expect(selected!.every((l) => l.documentNo == 'INV-24001'), isTrue);
    });

    test('multiple invoices: the higher Document_No is selected', () {
      final lines = [
        _line(documentNo: 'INV-24001', lineNo: 10000),
        _line(documentNo: 'INV-24010', lineNo: 10000),
        _line(documentNo: 'INV-24005', lineNo: 10000),
      ];

      final selected = selectLatestInvoiceLines(lines);

      expect(selected, hasLength(1));
      expect(selected!.single.documentNo, 'INV-24010');
    });

    test('never mixes lines from different Document_No values', () {
      final lines = [
        _line(documentNo: 'INV-24001', lineNo: 10000),
        _line(documentNo: 'INV-24010', lineNo: 10000),
        _line(documentNo: 'INV-24010', lineNo: 20000),
      ];

      final selected = selectLatestInvoiceLines(lines);

      expect(selected, hasLength(2));
      expect(selected!.every((l) => l.documentNo == 'INV-24010'), isTrue);
    });

    test('selection ignores Posting_Date entirely: an earlier-Document_No '
        'invoice with a later Posting_Date still loses', () {
      final lines = [
        _line(
          documentNo: 'INV-24001',
          lineNo: 10000,
          postingDate: DateTime(2026, 1, 1),
        ),
        _line(
          documentNo: 'INV-24002',
          lineNo: 10000,
          postingDate: DateTime(2020, 1, 1),
        ),
      ];

      final selected = selectLatestInvoiceLines(lines);

      expect(selected!.single.documentNo, 'INV-24002');
    });

    test('a single-digit vs double-digit suffix compares numerically '
        '(INV-9 loses to INV-10)', () {
      final lines = [
        _line(documentNo: 'INV-9', lineNo: 10000),
        _line(documentNo: 'INV-10', lineNo: 10000),
      ];

      final selected = selectLatestInvoiceLines(lines);

      expect(selected!.single.documentNo, 'INV-10');
    });
  });
}
