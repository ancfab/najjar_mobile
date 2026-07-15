// Fake InvoiceDocumentActions for tests that exercise the Print/Download
// PDF flow without invoking the real `printing` plugin.

import 'dart:async';
import 'dart:typed_data';

import 'package:anc_fabrics/services/invoice_document_actions.dart';

class RecordedDocumentAction {
  RecordedDocumentAction(this.bytes, this.filename);

  final Uint8List bytes;
  final String filename;
}

class FakeInvoiceDocumentActions implements InvoiceDocumentActions {
  FakeInvoiceDocumentActions({
    this.printResult,
    this.saveResult,
    this.pendingPrint,
    this.pendingSave,
  });

  /// `true`/`false` to resolve `printPdf` with, or an [Exception] to throw.
  /// Ignored when [pendingPrint] is set.
  Object? printResult;

  /// `true`/`false` to resolve `savePdf` with, or an [Exception] to throw.
  /// Ignored when [pendingSave] is set.
  Object? saveResult;

  /// When set, `printPdf` awaits this instead of resolving immediately —
  /// lets tests hold the print flow "in flight" to observe loading state
  /// and the duplicate-request guard.
  final Completer<bool>? pendingPrint;

  /// Same as [pendingPrint], for `savePdf`.
  final Completer<bool>? pendingSave;

  final List<RecordedDocumentAction> printCalls = [];
  final List<RecordedDocumentAction> saveCalls = [];

  @override
  Future<bool> printPdf(Uint8List bytes, String filename) async {
    printCalls.add(RecordedDocumentAction(bytes, filename));
    if (pendingPrint != null) return pendingPrint!.future;
    if (printResult is Exception) throw printResult as Exception;
    return printResult as bool? ?? true;
  }

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async {
    saveCalls.add(RecordedDocumentAction(bytes, filename));
    if (pendingSave != null) return pendingSave!.future;
    if (saveResult is Exception) throw saveResult as Exception;
    return saveResult as bool? ?? true;
  }
}
