// Shared fakes for the screens that produce a printed document: the PDF
// renderer, the native save/share handoff, the customer context, and the
// invoice-by-number lookup. None of them touch a platform channel, real
// HTTP, or secure storage.

import 'dart:typed_data';

import 'package:anc_fabrics/models/business_central/business_central_invoice_line.dart';
import 'package:anc_fabrics/models/order_document.dart';
import 'package:anc_fabrics/services/invoice_document_actions.dart';
import 'package:anc_fabrics/services/invoice_lines_by_number_service.dart';
import 'package:anc_fabrics/services/order_document_context.dart';
import 'package:anc_fabrics/services/order_pdf_service.dart';

/// Captures the document a screen asked to render, without building a PDF.
class FakeOrderPdfService implements OrderPdfService {
  final List<OrderDocument> documents = [];

  /// When set, thrown from [generate] instead of returning bytes.
  Object? error;

  @override
  Future<Uint8List> generate(OrderDocument document) async {
    documents.add(document);
    final failure = error;
    if (failure != null) throw failure;
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// Captures the native save/share handoff.
class FakeDocumentActions implements InvoiceDocumentActions {
  final List<String> savedFilenames = [];

  /// What [savePdf] resolves to — `false` stands for the user cancelling
  /// the share sheet.
  bool saveResult = true;

  @override
  Future<bool> printPdf(Uint8List bytes, String filename) async => true;

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async {
    savedFilenames.add(filename);
    return saveResult;
  }
}

class FakeOrderDocumentContext implements OrderDocumentContext {
  FakeOrderDocumentContext([this.data = const OrderDocumentContextData()]);

  final OrderDocumentContextData data;

  int loadCallCount = 0;

  @override
  Future<OrderDocumentContextData> load() async {
    loadCallCount++;
    return data;
  }
}

class FakeInvoiceLinesByNumberService implements InvoiceLinesByNumberService {
  FakeInvoiceLinesByNumberService({this.lines = const []});

  /// Returned from [fetchLines]; empty stands for "no invoice behind this
  /// row", which every caller must handle without inventing a document.
  List<BusinessCentralInvoiceLine> lines;

  final List<String> requestedDocumentNos = [];

  @override
  Future<List<BusinessCentralInvoiceLine>> fetchLines(String documentNo) async {
    requestedDocumentNos.add(documentNo);
    return lines;
  }
}
