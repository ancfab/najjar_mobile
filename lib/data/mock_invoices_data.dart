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
const List<Invoice> kMockInvoices = [
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
  ),
];
