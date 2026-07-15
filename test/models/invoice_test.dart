// Unit checks for the Invoice/InvoiceLineItem calculated fields: line total,
// subtotal, and total amount must derive from quantity/unit price/tax
// rather than being independently hardcoded anywhere.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/invoice.dart';

void main() {
  group('InvoiceLineItem.lineTotal', () {
    test('is quantity times unit price', () {
      const item = InvoiceLineItem(
        name: 'Egyptian Cotton Sateen (600TC)',
        description: 'Midnight Blue Dye Finish, 50m Roll',
        quantity: 12,
        unit: 'Rolls',
        unitPrice: 850.0,
      );

      expect(item.lineTotal, 10200.0);
    });

    test('changes when quantity or unit price changes', () {
      const item = InvoiceLineItem(
        name: 'Brushed Twill Weave',
        description: 'Industrial Strength Heavy-Weight, 30m Roll',
        quantity: 5,
        unit: 'Rolls',
        unitPrice: 410.0,
      );

      expect(item.lineTotal, 2050.0);
    });
  });

  group('Invoice.subtotal and Invoice.totalAmount', () {
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
          name: 'Egyptian Cotton Sateen (600TC)',
          description: 'Midnight Blue Dye Finish, 50m Roll',
          quantity: 12,
          unit: 'Rolls',
          unitPrice: 850.0,
        ),
        InvoiceLineItem(
          name: 'Brushed Twill Weave',
          description: 'Industrial Strength Heavy-Weight, 30m Roll',
          quantity: 5,
          unit: 'Rolls',
          unitPrice: 410.0,
        ),
      ],
      taxAmount: 612.50,
    );

    test('subtotal is the sum of every line item total', () {
      expect(invoice.subtotal, 12250.0);
    });

    test('totalAmount is subtotal plus tax', () {
      expect(invoice.totalAmount, invoice.subtotal + invoice.taxAmount);
      expect(invoice.totalAmount, 12862.50);
    });

    test('totalAmount stays in sync if the underlying items change', () {
      const withExtraItem = Invoice(
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
            quantity: 2,
            unit: 'Units',
            unitPrice: 100.0,
          ),
        ],
        taxAmount: 10.0,
      );

      expect(withExtraItem.subtotal, 200.0);
      expect(withExtraItem.totalAmount, 210.0);
    });
  });
}
