// Unit tests for LocalInvoicePdfService: verifies it produces a real,
// non-empty PDF document for both a fully populated invoice and one with no
// Payment Timeline events, without depending on any platform plugin.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/mock_invoices_data.dart';
import 'package:anc_fabrics/models/invoice.dart';
import 'package:anc_fabrics/services/invoice_pdf_service.dart';

void main() {
  group('LocalInvoicePdfService.generate', () {
    test('produces non-empty bytes starting with the PDF file signature', () async {
      final bytes = await const LocalInvoicePdfService().generate(
        kMockInvoices.first,
      );

      expect(bytes, isNotEmpty);
      // PDF files start with "%PDF-".
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('succeeds for an invoice with no timeline events', () async {
      const invoice = Invoice(
        invoiceNumber: '#INV-TEST',
        status: InvoiceStatus.paid,
        issuedDate: 'Oct 14, 2023',
        billedCompany: 'Test Co.',
        billedAddressLines: ['Line 1'],
        billedEmail: 'test@example.com',
        dueDate: 'Oct 28, 2023',
        paymentMethod: 'Bank Transfer',
        paymentReferenceMasked: '0000',
        items: [
          InvoiceLineItem(
            name: 'Item',
            description: 'Description',
            quantity: 1,
            unit: 'Units',
            unitPrice: 10.0,
          ),
        ],
        taxAmount: 1.0,
      );

      final bytes = await const LocalInvoicePdfService().generate(invoice);

      expect(bytes, isNotEmpty);
    });
  });
}
