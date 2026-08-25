import 'package:flutter/widgets.dart';

import '../localization/translations.dart';

/// Invoice status as understood by the Invoice Details UI.
///
/// Overdue, Draft) with the backend/API team before connecting live data.
/// Only [paid] is confirmed for the current mock design.
enum InvoiceStatus { paid }

/// English-only label for an [InvoiceStatus]. Used only where no
/// [BuildContext] is available (e.g. the invoice PDF export) — UI display
/// goes through [invoiceStatusLabel] instead so the shown text is translated.
String invoiceStatusLabelEn(InvoiceStatus status) {
  switch (status) {
    case InvoiceStatus.paid:
      return 'Paid';
  }
}

/// Localized human-readable label for an [InvoiceStatus]. Shared by
/// [InvoiceStatusBadge] so the display text only lives in one place.
String invoiceStatusLabel(BuildContext context, InvoiceStatus status) {
  switch (status) {
    case InvoiceStatus.paid:
      return context.t('invoiceStatus.paid');
  }
}

/// A single billable line item on an [Invoice] (e.g. one fabric roll SKU).
///
/// factory) once the Invoice Details API response format is confirmed.
class InvoiceLineItem {
  const InvoiceLineItem({
    required this.name,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  final String name;
  final String description;
  final int quantity;

  /// e.g. "Rolls".
  final String unit;

  final double unitPrice;

  /// [quantity] × [unitPrice], calculated rather than stored so it can never
  /// drift from the two values it's derived from.
  double get lineTotal => quantity * unitPrice;
}

/// A single completed event in an invoice's Payment Timeline (e.g. "Payment
/// Received"), newest-first order is the caller's responsibility (see
/// [Invoice.timelineEvents]).
///
/// the endpoint and response shape are confirmed. Timeline events are
/// currently mock-only, populated directly in `mock_invoices_data.dart`.
class InvoiceTimelineEvent {
  const InvoiceTimelineEvent({required this.title, required this.occurredAt});

  /// e.g. "Payment Received".
  final String title;

  final DateTime occurredAt;
}

/// Temporary Invoice Details logistics/shipment info: a free-text status
/// label (e.g. "In Production") and an estimated delivery date, shown on
/// [InvoiceLogisticsStatusCard]. [statusLabel] is a plain string rather than
class InvoiceLogisticsInfo {
  const InvoiceLogisticsInfo({this.statusLabel, this.estimatedDeliveryDate});

  // and localization rules before replacing this temporary display label with
  // a typed status enum or backend status-code mapping.
  /// Display-only logistics status text (e.g. "In Production"). Null/blank
  /// means no status is shown.
  final String? statusLabel;

  // promised, or committed delivery date and whether timezone conversion is
  // required before displaying backend data.
  /// Estimated delivery date. Null means no estimate is shown.
  final DateTime? estimatedDeliveryDate;
}

/// A single invoice's Invoice Details data.
///
/// Only the fields needed for the current Invoice Details screen sections
/// are modeled here — later sections (notes, payment history, footer) will
/// extend this once their screenshots/scope are provided.
///
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
    required this.items,
    required this.taxAmount,
    this.timelineEvents = const [],
    this.clientVisibleNote,
    this.logisticsInfo,
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

  /// Billable line items shown in the Invoice line-items table, in display
  /// order.
  final List<InvoiceLineItem> items;

  /// Flat sample tax amount for the mock invoice.
  ///
  /// accounting backend once confirmed. This fixed sample value carries no
  /// real tax rule (no rate, jurisdiction, or product-tax-category logic) —
  /// it exists only so the Totals section has a value to display and sum.
  final double taxAmount;

  /// Payment Timeline events, in newest-first display order. Empty by
  /// default so existing/test invoices that don't set it don't need to
  /// change; the Payment Timeline section itself renders nothing when this
  /// is empty.
  final List<InvoiceTimelineEvent> timelineEvents;

  /// Free-text note shown in the Invoice Details screen's Internal Notes
  /// section. Null/empty means no note is displayed.
  ///
  // back-office-only. If confirmed as back-office-only, stop exposing this
  // field in the mobile app and remove InvoiceNotesSection from InvoiceInfoCard.
  final String? clientVisibleNote;

  /// Logistics Status card fields (status label + estimated delivery date)
  /// shown on the Invoice Details screen. Null means the section renders
  /// nothing — see [InvoiceLogisticsInfo] for why this is mock/temporary.
  final InvoiceLogisticsInfo? logisticsInfo;

  /// Sum of every line item's [InvoiceLineItem.lineTotal].
  double get subtotal => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  /// [subtotal] + [taxAmount], calculated rather than stored so it can never
  /// drift from the line items or tax amount.
  double get totalAmount => subtotal + taxAmount;
}
