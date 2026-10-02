import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/order_document.dart';
import '../utils/date_time_format.dart';

/// Prepares the printable/downloadable PDF for one sales order.
abstract class OrderPdfService {
  Future<Uint8List> generate(OrderDocument document);
}

/// Generates the Sales Quotation / Zebra Sales Quotation document
/// on-device with `package:pdf`, laid out to match ANC's existing printed
/// forms: a boxed customer/invoice header, the goods table (with the
/// Zebra form's extra Length/Width columns), the balance and last-payment
/// block beside the invoice totals, and the Delivery Note slip beneath a
/// cut line.
///
/// Every field the printed form shows but the ANC API does not yet return
/// — invoice number and date, TRN, payment method, customer zone — is
/// optional on [OrderDocument] and omitted when absent, never printed as
/// an empty labelled box or a placeholder. Once the backend returns them,
/// filling those fields is all that is needed here.
///
/// An Arabic-capable TTF is loaded as a font *fallback* rather than the
/// base font: the labels are English and keep the crisp built-in base
/// font, while an Arabic customer name or address — which the built-in
/// fonts have no glyphs for at all — still renders instead of coming out
/// blank.
class LocalOrderPdfService implements OrderPdfService {
  LocalOrderPdfService({this.compress = true});

  /// Whether the generated PDF's streams are compressed. Production keeps
  /// this on, since the embedded Arabic font makes an uncompressed
  /// document several times larger to share or print. Tests turn it off so
  /// the document's own text is readable in the bytes, matching
  /// `buildAccountStatementPdfBytes`' convention.
  final bool compress;

  static const String _arabicFontAsset = 'assets/fonts/NotoNaskhArabic.ttf';

  /// Loaded once per instance: the font bytes are ~300 KB, and a customer
  /// exporting several orders in a row should pay that parse cost once.
  pw.Font? _arabicFont;

  Future<pw.Font?> _loadArabicFont() async {
    final cached = _arabicFont;
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(_arabicFontAsset);
      final font = pw.Font.ttf(data);
      _arabicFont = font;
      return font;
    } catch (_) {
      // A missing/unreadable font asset must not cost the user their
      // document: Latin text still renders on the built-in base fonts,
      // and this is the only thing that degrades.
      return null;
    }
  }

  @override
  Future<Uint8List> generate(OrderDocument document) async {
    final arabicFont = await _loadArabicFont();
    final doc = pw.Document(
      compress: compress,
      theme: pw.ThemeData.withFont(
        fontFallback: [?arabicFont],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _title(document),
          pw.SizedBox(height: 10),
          _headerBox(document),
          pw.SizedBox(height: 12),
          _goodsTable(document),
          pw.SizedBox(height: 12),
          _balanceAndTotals(document),
          pw.SizedBox(height: 24),
          _cutLine(),
          pw.SizedBox(height: 12),
          _deliveryNote(document),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _title(OrderDocument document) {
    return pw.Center(
      child: pw.Text(
        document.isZebra ? 'Zebra Sales Quotation' : 'Sales Quotation',
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  /// The boxed header: customer identity on the left, document numbers and
  /// dates on the right, exactly as the printed form pairs them.
  pw.Widget _headerBox(OrderDocument document) {
    return _bordered(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Customer Details :',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  _value(document.customerNo),
                  _value(document.customerName),
                  if (document.customerZone != null)
                    _value(document.customerZone!),
                  if (document.customerAddress != null)
                    _value(document.customerAddress!),
                  if (document.customerCountry != null)
                    _value(document.customerCountry!),
                  if (document.customerPhone != null) ...[
                    pw.SizedBox(height: 4),
                    _labelledInline('Phone', document.customerPhone!),
                  ],
                  if (document.trnNo != null)
                    _labelledInline('TRN No', document.trnNo!),
                ],
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              children: [
                if (document.invoiceNo != null)
                  _headerCell('INVOICE NO.', document.invoiceNo!),
                if (document.invoiceDate != null)
                  _headerCell(
                    'INVOICE DATE',
                    formatNumericDate(document.invoiceDate!),
                  ),
                _headerCell('Order No.', document.orderNo),
                if (document.orderDate != null)
                  _headerCell(
                    'Order Date',
                    formatNumericDate(document.orderDate!),
                  ),
                if (document.paymentMethod != null)
                  _headerCell('Payment Method', document.paymentMethod!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _goodsTable(OrderDocument document) {
    final headers = <String>[
      'Sr.No',
      'Description of Goods',
      'U.O.M/Qty',
      if (document.isZebra) 'Length',
      if (document.isZebra) 'Width',
      'Price',
      'Amount',
      'Disc',
      'Amount\n(After Disc.)',
    ];

    final rows = <List<String>>[
      for (var index = 0; index < document.lines.length; index++)
        _lineCells(document, document.lines[index], index + 1),
      [
        '',
        'TOTAL',
        _number(document.totalQuantity),
        if (document.isZebra) '',
        if (document.isZebra) '',
        '',
        _number(document.totalAmount),
        _number(document.totalDiscount),
        _number(document.netAmount),
      ],
    ];

    // Built by hand rather than through TableHelper so each cell can carry
    // its own text direction: a Business Central description comes back in
    // Arabic as readily as in English, and TableHelper gives every cell the
    // same LTR direction (see [_text]).
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.8),
        1: const pw.FlexColumnWidth(3.2),
      },
      children: [
        pw.TableRow(
          children: [
            for (final header in headers)
              _cell(header, bold: true, align: pw.TextAlign.center),
          ],
        ),
        for (var index = 0; index < document.lines.length; index++)
          pw.TableRow(
            children: [
              for (var column = 0; column < rows[index].length; column++)
                _cell(
                  rows[index][column],
                  align: _columnAlignment(column),
                ),
            ],
          ),
        pw.TableRow(
          children: [
            for (var column = 0; column < rows.last.length; column++)
              _cell(
                rows.last[column],
                bold: true,
                align: _columnAlignment(column),
              ),
          ],
        ),
      ],
    );
  }

  /// Sr.No centred, the description left, every figure right — the printed
  /// form's own column alignment.
  pw.TextAlign _columnAlignment(int column) => switch (column) {
    0 => pw.TextAlign.center,
    1 => pw.TextAlign.left,
    _ => pw.TextAlign.right,
  };

  pw.Widget _cell(String value, {bool bold = false, pw.TextAlign? align}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: _text(value, bold: bold, align: align),
    );
  }

  List<String> _lineCells(
    OrderDocument document,
    OrderDocumentLine line,
    int srNo,
  ) {
    return [
      '$srNo',
      line.description,
      line.unitOfMeasureCode == null
          ? _number(line.quantity)
          : '${_number(line.quantity)} ${line.unitOfMeasureCode}',
      if (document.isZebra) _number(line.length ?? 0),
      if (document.isZebra) _number(line.width ?? 0),
      _number(line.unitPrice),
      _number(line.amount),
      _number(line.discountAmount ?? 0),
      _number(line.amountAfterDiscount),
    ];
  }

  /// The account block (left) beside the invoice totals (right), the way
  /// the printed form pairs them. The account block is omitted entirely
  /// when no customer-details snapshot was available, rather than printing
  /// a zero balance that would read as a settled account.
  pw.Widget _balanceAndTotals(OrderDocument document) {
    final hasAccountBlock =
        document.balance != null ||
        document.lastPaymentAmount != null ||
        document.lastPaymentDate != null;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: hasAccountBlock
              ? pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (document.balance != null)
                      _boxedRow('Balance', _money(document, document.balance!)),
                    if (document.lastPaymentDate != null)
                      _boxedRow(
                        'Last Payment Date',
                        formatNumericDate(document.lastPaymentDate!),
                      ),
                    if (document.lastPaymentAmount != null)
                      _boxedRow(
                        'Last Payment Amount',
                        _money(document, document.lastPaymentAmount!),
                      ),
                    if (document.note != null)
                      _boxedRow('Note', document.note!),
                  ],
                )
              : pw.SizedBox(),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            children: [
              _boxedRow(
                'Invoice Amount',
                _money(document, document.totalAmount),
              ),
              _boxedRow('Discount', _money(document, document.totalDiscount)),
              _boxedRow(
                'Net Amount',
                _money(document, document.netAmount),
                emphasized: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _cutLine() {
    return pw.Row(
      children: List.generate(
        60,
        (_) => pw.Expanded(
          child: pw.Text(
            '= ',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );
  }

  /// The Delivery Note slip. Prints only the fields this document actually
  /// has: a backend that later returns the invoice number/date or the
  /// customer's zone fills the matching rows automatically.
  pw.Widget _deliveryNote(OrderDocument document) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'Delivery Note',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  _boxedRow('Customer Name', document.customerName),
                  if (document.customerZone != null)
                    _boxedRow('Customer Zone', document.customerZone!),
                  if (document.customerPhone != null)
                    _boxedRow('Contact Number', document.customerPhone!),
                  if (document.note != null) _boxedRow('Memo', document.note!),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                children: [
                  if (document.invoiceDate != null)
                    _boxedRow(
                      'Invoice Date',
                      formatNumericDate(document.invoiceDate!),
                    ),
                  if (document.invoiceNo != null)
                    _boxedRow('Invoice No.', document.invoiceNo!),
                  _boxedRow('Order No.', document.orderNo),
                  _boxedRow(
                    'Net Amount',
                    _money(document, document.netAmount),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _bordered({required pw.Widget child}) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: child,
    );
  }

  pw.Widget _headerCell(String label, String value) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(width: 0.5),
          bottom: pw.BorderSide(width: 0.5),
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _text(label, bold: true),
          pw.SizedBox(width: 8),
          pw.Flexible(child: _text(value, align: pw.TextAlign.right)),
        ],
      ),
    );
  }

  pw.Widget _boxedRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _text(label, bold: emphasized),
          pw.SizedBox(width: 8),
          pw.Flexible(
            child: _text(
              value,
              bold: emphasized,
              align: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _value(String text) => _text(text, fontSize: 9);

  /// Any Arabic letter, including the Presentation Forms blocks a backend
  /// may already have substituted.
  static final RegExp _arabicPattern = RegExp(
    r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]',
  );

  static bool _isArabic(String value) => _arabicPattern.hasMatch(value);

  /// Builds a text widget that renders Arabic correctly.
  ///
  /// `package:pdf` only joins Arabic letters into their connected forms and
  /// reorders a line right-to-left when the surrounding text direction is
  /// RTL; left to its default LTR it draws the isolated letters in typed
  /// order, which is the "messed up" rendering a customer name came out as.
  /// Latin text keeps LTR, so an order number or amount is never flipped.
  pw.Widget _text(
    String value, {
    double fontSize = 8,
    bool bold = false,
    pw.TextAlign? align,
  }) {
    final arabic = _isArabic(value);
    final style = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      // Arabic text asks for the Arabic face directly rather than leaving
      // the base font to miss every glyph and fall back; Latin text keeps
      // the crisper built-in base font.
      font: arabic ? _arabicFont : null,
    );
    final text = pw.Text(
      value,
      style: style,
      textAlign: align ?? (arabic ? pw.TextAlign.right : null),
      textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
    );
    if (!arabic) return text;
    return pw.Directionality(textDirection: pw.TextDirection.rtl, child: text);
  }

  pw.Widget _labelledInline(String label, String value) {
    return pw.Row(
      children: [
        _text('$label : ', fontSize: 9, bold: true),
        _text(value, fontSize: 9),
      ],
    );
  }

  /// Two decimals, thousands-separated — the form's own number format.
  String _number(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts.first.replaceAll('-', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    final sign = value < 0 ? '-' : '';
    return '$sign$buffer.${parts.last}';
  }

  /// A monetary figure prefixed with the document's currency when one is
  /// known — never a guessed symbol when it isn't.
  String _money(OrderDocument document, double value) {
    final code = document.currencyCode?.trim();
    final amount = _number(value);
    return code == null || code.isEmpty ? amount : '$code $amount';
  }
}
