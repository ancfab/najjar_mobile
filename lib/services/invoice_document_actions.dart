import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Thin wrapper around the `printing` plugin's static functions so the
/// native print/save flows can be exercised in tests without invoking the
/// real platform plugin — mirrors `UrlLauncherClient`'s role for
/// `url_launcher`.
abstract class InvoiceDocumentActions {
  /// Opens the native print dialog for [bytes]. Resolves `true` if the
  /// document was printed (or otherwise handed off, e.g. "Save as PDF" from
  /// within the print dialog), `false` if the user cancelled. May throw if
  /// the platform print flow itself fails.
  Future<bool> printPdf(Uint8List bytes, String filename);

  /// Opens the native share/save sheet for [bytes], letting the user save
  /// or export it (e.g. to Files on iOS, or a share target on Android).
  /// Resolves `true` if completed, `false` if cancelled. May throw if the
  /// platform share flow itself fails.
  Future<bool> savePdf(Uint8List bytes, String filename);
}

class PrintingInvoiceDocumentActions implements InvoiceDocumentActions {
  const PrintingInvoiceDocumentActions();

  @override
  Future<bool> printPdf(Uint8List bytes, String filename) {
    return Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) {
    return Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
