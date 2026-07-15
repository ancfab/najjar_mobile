/// Builds a filesystem-safe `invoice-<number>.pdf` filename from a raw
/// [invoiceNumber] (e.g. `#INV-8821` -> `invoice-INV-8821.pdf`), stripping
/// everything outside `[A-Za-z0-9-_]` so it's safe to hand to native
/// print/share/save flows on both Android and iOS.
String invoicePdfFilename(String invoiceNumber) {
  final sanitized = invoiceNumber
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final base = sanitized.isEmpty ? 'invoice' : sanitized;
  return 'invoice-$base.pdf';
}
