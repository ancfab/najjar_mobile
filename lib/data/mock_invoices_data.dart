import '../models/invoice.dart';

/// Invoice number of the only sample invoice currently available.
///
/// TODO: Remove this once Fabric Orders link to a real invoice number (see
/// `OrderDetailScreen._openInvoice`), rather than every order opening the
/// same sample invoice.
const String kSampleInvoiceNumber = '#INV-8821';

/// Mock Invoice Details data.
///
/// TODO: Replace with the real Invoice Details API once the endpoint and
/// response shape are confirmed. This is the only sample invoice available
/// until then.
///
/// Not `const` because [InvoiceTimelineEvent.occurredAt] holds `DateTime`
/// values, and `DateTime` has no const constructor.
final List<Invoice> kMockInvoices = [
  Invoice(
    invoiceNumber: kSampleInvoiceNumber,
    status: InvoiceStatus.paid,
    issuedDate: 'Oct 14, 2023',
    billedCompany: 'Luxury Linens Ltd.',
    billedAddressLines: [
      '882 High Street, Suite 402',
      'London, W1J 7JX',
      'United Kingdom',
    ],
    billedEmail: 'accounts@luxurylinens.com',
    dueDate: 'Oct 28, 2023',
    paymentMethod: 'Bank Transfer',
    paymentReferenceMasked: '4492',
    items: [
      InvoiceLineItem(
        name: 'Egyptian Cotton Sateen (600TC)',
        description: 'Midnight Blue Dye Finish, 50m Roll',
        quantity: 12,
        unit: 'Rolls',
        unitPrice: 850.0,
      ),
      InvoiceLineItem(
        name: 'Brushed Twill Weave',
        description: 'Industrial Strength Heavy-Weight, 30m Roll',
        quantity: 5,
        unit: 'Rolls',
        unitPrice: 410.0,
      ),
    ],
    // Flat sample tax amount — see [Invoice.taxAmount] for why this is not a
    // real tax rule.
    taxAmount: 612.50,
    // TODO(product): Confirm whether invoice notes are client-visible or
    // back-office-only. If confirmed as back-office-only, stop exposing this
    // field in the mobile app and remove InvoiceNotesSection from
    // InvoiceInfoCard.
    clientVisibleNote:
        'Thank you for your continued business. Please reference invoice '
        '#INV-8821 in any correspondence regarding this payment.',
    // TODO(api): Replace this temporary mock logistics information with the
    // confirmed Invoice API/backend fields and status codes once the contract is
    // available.
    logisticsInfo: InvoiceLogisticsInfo(
      statusLabel: 'In Production',
      estimatedDeliveryDate: DateTime(2023, 10, 30),
    ),
    // TODO: Replace with timeline events from the real Invoice API/
    // accounting backend once confirmed — this fixed mock list is the only
    // source of Payment Timeline data for now. Newest-first order.
    timelineEvents: [
      InvoiceTimelineEvent(
        title: 'Payment Received',
        occurredAt: DateTime(2023, 10, 16, 9, 12),
      ),
      InvoiceTimelineEvent(
        title: 'Invoice Sent',
        occurredAt: DateTime(2023, 10, 14, 14, 45),
      ),
      InvoiceTimelineEvent(
        title: 'Invoice Generated',
        occurredAt: DateTime(2023, 10, 14, 13, 20),
      ),
    ],
  ),
];
