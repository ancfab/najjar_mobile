/// Price breakdown for a single order, shown on the Order Detail screen's
/// Price Breakdown card.
///
/// Amounts are stored pre-formatted for display (matching [FabricOrder.price]
/// elsewhere in this app) rather than as raw numbers, since no currency
/// formatting/locale requirements have been confirmed yet.
///
/// once subtotal, shipping, VAT, total amount, currency, and invoice
/// availability fields are confirmed.
class OrderPriceBreakdown {
  const OrderPriceBreakdown({
    required this.subtotal,
    required this.shipping,
    required this.vat,
    required this.totalAmount,
  });

  final String subtotal;
  final String shipping;
  final String vat;
  final String totalAmount;
}
