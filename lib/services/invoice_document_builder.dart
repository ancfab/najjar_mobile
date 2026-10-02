import '../models/business_central/business_central_invoice_line.dart';
import '../models/order_document.dart';
import 'order_document_context.dart';

/// Builds the printable document for one invoice from its own lines plus
/// the shared customer context, so the Invoices list and Account Balance's
/// Quick History render the identical document from the identical rules.
///
/// Unlike a sales order, an invoice already carries its own number, posting
/// date, payment method and currency, so those fields are filled rather
/// than omitted. Anything a line genuinely lacks stays null and is left off
/// the document (see [OrderDocument]).
///
/// [lines] must all belong to one invoice; the caller groups them (the
/// Invoices screen already groups by `Document_No`).
OrderDocument buildInvoiceDocument({
  required List<BusinessCentralInvoiceLine> lines,
  OrderDocumentContextData? context,
}) {
  if (lines.isEmpty) {
    throw ArgumentError.value(lines, 'lines', 'must not be empty');
  }

  final first = lines.first;
  final currencyCode = lines
      .map((line) => line.currencyCode.trim())
      .firstWhere((code) => code.isNotEmpty, orElse: () => '');
  final paymentMethod = lines
      .map((line) => line.paymentMethod?.trim() ?? '')
      .firstWhere((method) => method.isNotEmpty, orElse: () => '');
  final orderNo = lines
      .map((line) => line.orderNo.trim())
      .firstWhere((no) => no.isNotEmpty, orElse: () => '');

  return OrderDocument(
    // The document's own number is the invoice number; the order number is
    // shown too when the invoice carries one.
    orderNo: orderNo.isEmpty ? first.documentNo : orderNo,
    invoiceNo: first.documentNo,
    invoiceDate: first.postingDate,
    orderDate: first.postingDate,
    customerNo: first.sellToCustomerNo,
    customerName: first.sellToCustomerName,
    paymentMethod: paymentMethod.isEmpty ? null : paymentMethod,
    currencyCode: currencyCode.isEmpty ? null : currencyCode,
    customerAddress: context?.customerAddress,
    customerPhone: context?.customerPhone,
    balance: context?.balance,
    lastPaymentAmount: context?.lastPaymentAmount,
    lastPaymentDate: context?.lastPaymentDate,
    lines: [
      for (final line in lines)
        OrderDocumentLine(
          description: line.description.trim().isEmpty
              ? line.itemNo
              : line.description,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          amount: line.amount,
        ),
    ],
  );
}
