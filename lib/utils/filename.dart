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

/// Builds a filesystem-safe `account-statement-<yyyy-MM-dd>.pdf` filename
/// from [generatedAt], safe to hand to native print/share/save flows on
/// both Android and iOS.
String accountStatementPdfFilename(DateTime generatedAt) {
  final year = generatedAt.year.toString().padLeft(4, '0');
  final month = generatedAt.month.toString().padLeft(2, '0');
  final day = generatedAt.day.toString().padLeft(2, '0');
  return 'account-statement-$year-$month-$day.pdf';
}
