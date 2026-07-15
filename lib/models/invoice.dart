/// Invoice status as understood by the Invoice Details UI.
///
/// TODO: Confirm the complete list of possible invoice statuses (e.g. Paid,
/// Overdue, Draft) with the backend/API team before connecting live data.
/// Only [paid] is confirmed for the current mock design.
enum InvoiceStatus { paid }

/// Human-readable label for an [InvoiceStatus]. Shared by [InvoiceStatusBadge]
/// so the display text only lives in one place.
String invoiceStatusLabel(InvoiceStatus status) {
  switch (status) {
    case InvoiceStatus.paid:
      return 'Paid';
  }
}

/// A single invoice's Invoice Details data.
///
/// Only the fields needed for the current Invoice Details screen section are
/// modeled here — later sections (line items, totals, notes, payment
/// history) will extend this once their screenshots/scope are provided.
///
/// TODO: Replace with a backend-shaped model (likely with a `fromJson`
/// factory) once the Invoice Details API response format is confirmed.
class Invoice {
  const Invoice({
    required this.invoiceNumber,
    required this.status,
    required this.issuedDate,
    required this.billedCompany,
    required this.billedAddressLines,
    required this.billedEmail,
    required this.dueDate,
    required this.paymentMethod,
    required this.paymentReferenceMasked,
  });

  /// e.g. "#INV-8821".
  final String invoiceNumber;

  final InvoiceStatus status;

  /// Pre-formatted display date (e.g. "Oct 14, 2023").
  final String issuedDate;

  final String billedCompany;

  /// Each entry is one displayed address line, in display order.
  final List<String> billedAddressLines;

  final String billedEmail;

  /// Pre-formatted display date (e.g. "Oct 28, 2023").
  final String dueDate;

  /// e.g. "Bank Transfer".
  final String paymentMethod;

  /// Masked trailing digits shown next to [paymentMethod] (e.g. "4492" for
  /// "Ending ...4492").
  final String paymentReferenceMasked;
}
