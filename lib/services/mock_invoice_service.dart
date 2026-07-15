import '../data/mock_invoices_data.dart';
import '../models/invoice.dart';

/// Supplies Invoice Details data for the Invoice Details screen.
///
/// This is the single service/repository boundary the Invoice Details
/// screen calls through — it never reads [kMockInvoices] itself, so the
/// underlying data source (mock vs. real API) can change without touching
/// the screen.
///
/// TODO: Replace mock invoice fetching with the real Invoice Details API
/// once the endpoint is confirmed.
class MockInvoiceService {
  const MockInvoiceService();

  /// Fetches mock Invoice Details data for the Invoice Details screen, keyed
  /// by [Invoice.invoiceNumber]. Throws a [StateError] if no mock invoice
  /// matches [invoiceNumber], which the Invoice Details screen surfaces as
  /// its normal error/retry state.
  Future<Invoice> fetchInvoice(String invoiceNumber) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return kMockInvoices.firstWhere(
      (candidate) => candidate.invoiceNumber == invoiceNumber,
      orElse: () => throw StateError('Invoice $invoiceNumber not found'),
    );
  }
}
