import '../models/business_central/business_central_invoice_line.dart';
import '../utils/document_no_comparator.dart';

/// Purpose: Pure, side-effect-free grouping/selection logic over already-
/// fetched invoice lines, kept separate from [InvoiceLookupService]'s
/// transport concerns so it can be tested without any HTTP/session
/// plumbing.
///
/// Groups [lines] by [BusinessCentralInvoiceLine.documentNo] and returns the
/// full line list belonging to the invoice with the highest `Document_No`
/// under [compareDocumentNoNatural] — never by [BusinessCentralInvoiceLine.
/// postingDate] (deliberately unused here: the confirmed contract requires
/// picking the higher `Document_No`, and `Posting_Date` is not even
/// reliably present on the live response — see that field's own doc
/// comment).
///
/// Returns `null` when [lines] is empty (no related invoice for the order).
/// The returned list preserves [lines]' original relative order for that
/// invoice's rows; it is never re-sorted by line number or anything else.
List<BusinessCentralInvoiceLine>? selectLatestInvoiceLines(
  List<BusinessCentralInvoiceLine> lines,
) {
  if (lines.isEmpty) return null;

  final groups = <String, List<BusinessCentralInvoiceLine>>{};
  for (final line in lines) {
    groups.putIfAbsent(line.documentNo, () => []).add(line);
  }

  final documentNumbers = groups.keys.toList()..sort(compareDocumentNoNatural);
  return groups[documentNumbers.last];
}
