import '../models/business_central/business_central_invoice_line.dart';
import 'invoices_service.dart';

/// Purpose: Finds every line of one invoice by its `Document_No`, for a
/// caller that knows the invoice number but not its lines — Quick History,
/// whose rows come from the ledger and carry only the document number.
///
/// The invoices endpoint filters by `order_no` only, so this pages the list
/// and matches client-side. Invoices come back newest first, so the row a
/// customer just tapped in Quick History is normally on the first page;
/// [maxPages] caps how far back this will look rather than walking an
/// entire history to prove a negative.
///
/// Returns an empty list when the number isn't among the pages scanned —
/// including the ordinary case of a ledger row that is not an invoice at
/// all (a payment, say). The caller tells the user, rather than this
/// inventing a document.
abstract interface class InvoiceLinesByNumberService {
  Future<List<BusinessCentralInvoiceLine>> fetchLines(String documentNo);
}

class ApiInvoiceLinesByNumberService implements InvoiceLinesByNumberService {
  ApiInvoiceLinesByNumberService({
    InvoicesService? invoicesService,
    this.maxPages = 5,
  }) : _invoicesService = invoicesService,
       _ownsService = invoicesService == null;

  final InvoicesService? _invoicesService;
  final bool _ownsService;

  /// How many pages back this will look before giving up.
  final int maxPages;

  @override
  Future<List<BusinessCentralInvoiceLine>> fetchLines(String documentNo) async {
    final wanted = documentNo.trim();
    if (wanted.isEmpty) return const [];

    final service = _invoicesService ?? InvoicesService();
    try {
      await service.loadFirstPage();
      var pagesLoaded = 1;
      var matches = _matching(service.lines, wanted);

      // Stop as soon as the invoice is found: its lines are contiguous
      // within one response, and a later page cannot add lines to an
      // invoice an earlier page already carried in full.
      while (matches.isEmpty &&
          service.hasNextPage &&
          pagesLoaded < maxPages) {
        await service.loadNextPage();
        pagesLoaded++;
        matches = _matching(service.lines, wanted);
      }
      return matches;
    } finally {
      if (_ownsService) service.close();
    }
  }

  List<BusinessCentralInvoiceLine> _matching(
    List<BusinessCentralInvoiceLine> lines,
    String documentNo,
  ) {
    return [
      for (final line in lines)
        if (line.documentNo.trim() == documentNo) line,
    ];
  }
}
