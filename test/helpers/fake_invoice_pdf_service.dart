// Fake InvoicePdfService for tests that exercise the Print/Download PDF
// flow without generating a real PDF document.

import 'dart:async';
import 'dart:typed_data';

import 'package:anc_fabrics/models/invoice.dart';
import 'package:anc_fabrics/services/invoice_pdf_service.dart';

class FakeInvoicePdfService implements InvoicePdfService {
  FakeInvoicePdfService({this.bytes, this.pending});

  /// Bytes to resolve with, or an [Exception] to throw. Ignored when
  /// [pending] is set.
  Object? bytes;

  /// When set, `generate` awaits this instead of resolving immediately —
  /// lets tests hold generation "in flight" to observe loading state and
  /// the duplicate-request guard.
  final Completer<Uint8List>? pending;

  final List<Invoice> generatedFor = [];

  @override
  Future<Uint8List> generate(Invoice invoice) async {
    generatedFor.add(invoice);
    if (pending != null) return pending!.future;
    if (bytes is Exception) throw bytes as Exception;
    return bytes as Uint8List? ?? Uint8List.fromList([1, 2, 3]);
  }
}
