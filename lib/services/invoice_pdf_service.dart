import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/invoice.dart';
import '../utils/currency.dart';

/// Prepares the printable/downloadable PDF document for an [Invoice].
abstract class InvoicePdfService {
  Future<Uint8List> generate(Invoice invoice);
}

/// Generates the invoice PDF entirely on-device from the [Invoice] model
/// using `package:pdf`, covering only the printable financial invoice
/// fields (status/number/issued date, Billed To, Due Date/Payment Method,
/// line items, Subtotal/Tax/Total Amount).
///
/// Deliberately excludes [Invoice.timelineEvents]: the Payment Timeline is
/// an app-activity component of the Invoice Details screen, not part of
/// the printable financial invoice — it stays visible in the mobile UI but
/// is never rendered into this document.
///
/// TODO: No documented Invoice PDF backend endpoint exists yet (see the
/// TODOs on [Invoice] and `mock_invoices_data.dart` — all invoice data is
/// still mock-only). Once a real endpoint is confirmed, either replace this
/// with an [InvoicePdfService] that fetches the backend-rendered PDF bytes
/// directly, or keep local generation as an offline fallback and delegate
/// to the endpoint when reachable.
class LocalInvoicePdfService implements InvoicePdfService {
  const LocalInvoicePdfService();

  @override
  Future<Uint8List> generate(Invoice invoice) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          _buildHeader(invoice),
          pw.SizedBox(height: 20),
          _buildBilledTo(invoice),
          pw.SizedBox(height: 16),
          _buildDueDateAndPayment(invoice),
          pw.SizedBox(height: 20),
          _buildLineItemsTable(invoice),
          pw.SizedBox(height: 12),
          _buildTotals(invoice),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildHeader(Invoice invoice) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'INVOICE',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(invoice.invoiceNumber),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(invoiceStatusLabelEn(invoice.status).toUpperCase()),
            pw.SizedBox(height: 4),
            pw.Text('Issued: ${invoice.issuedDate}'),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildBilledTo(Invoice invoice) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionLabel('BILLED TO'),
        pw.SizedBox(height: 4),
        pw.Text(
          invoice.billedCompany,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        for (final line in invoice.billedAddressLines) pw.Text(line),
        pw.Text(invoice.billedEmail),
      ],
    );
  }

  pw.Widget _buildDueDateAndPayment(Invoice invoice) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionLabel('DUE DATE'),
              pw.SizedBox(height: 4),
              pw.Text(invoice.dueDate),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionLabel('PAYMENT METHOD'),
              pw.SizedBox(height: 4),
              pw.Text(
                '${invoice.paymentMethod} '
                '(Ending ...${invoice.paymentReferenceMasked})',
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildLineItemsTable(Invoice invoice) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Item', 'Qty', 'Unit Price', 'Total'],
      data: [
        for (final item in invoice.items)
          [
            '${item.name}\n${item.description}',
            '${item.quantity} ${item.unit}',
            formatCurrency(item.unitPrice),
            formatCurrency(item.lineTotal),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _buildTotals(Invoice invoice) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        _totalRow('Subtotal', invoice.subtotal),
        _totalRow('Tax', invoice.taxAmount),
        _totalRow('Total Amount', invoice.totalAmount, emphasized: true),
      ],
    );
  }

  pw.Widget _totalRow(String label, double amount, {bool emphasized = false}) {
    final style = pw.TextStyle(
      fontWeight: emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(width: 120, child: pw.Text(label, style: style)),
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              formatCurrency(amount),
              style: style,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionLabel(String label) {
    return pw.Text(
      label,
      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    );
  }
}
