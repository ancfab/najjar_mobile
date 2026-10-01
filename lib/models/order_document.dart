/// Purpose: Everything one printable Sales Quotation / Zebra Sales
/// Quotation document shows, already resolved from the sources that own
/// each part (order lines, the customer-details snapshot, the stored
/// session/profile) so `OrderPdfService` renders a document without
/// reaching for data itself.
///
/// Responsibilities:
/// - Make every field the paper form shows but the backend does not yet
///   return — invoice number/date, TRN, payment method, customer zone —
///   explicitly optional, so the renderer omits that row rather than
///   printing an invented value or an empty labelled box.
/// - Keep [isZebra] the single switch between the two layouts, so the
///   Length/Width columns and the "Zebra Sales Quotation" title can never
///   disagree about which document this is.
///
/// Must not:
/// - Hold display-formatted strings for monetary values; formatting is the
///   renderer's job, from these raw numbers.
library;

/// One line of a printable order document.
class OrderDocumentLine {
  const OrderDocumentLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    this.unitOfMeasureCode,
    this.discountAmount,
    this.length,
    this.width,
  });

  /// What the "Description of Goods" column prints — the line's item
  /// description, or its item number when Business Central returned no
  /// description for it.
  final String description;

  final double quantity;
  final double unitPrice;
  final double amount;

  /// Printed next to [quantity] (e.g. "2 MT"). Null for a line with no
  /// unit of measure, such as a delivery charge, which prints the bare
  /// quantity.
  final String? unitOfMeasureCode;

  /// Absolute discount on this line, printed in the Disc column. Null is
  /// printed as 0.00 — a line with no discount is not a line with unknown
  /// discount.
  final double? discountAmount;

  /// Cut-to-size dimensions, Zebra documents only. Null on a Zebra line
  /// that carries none (e.g. a delivery charge), which prints 0.00 the way
  /// the paper form does.
  final double? length;
  final double? width;

  /// The Amount (After Disc.) column: [amount] less [discountAmount].
  double get amountAfterDiscount => amount - (discountAmount ?? 0);
}

/// One printable Sales Quotation or Zebra Sales Quotation.
class OrderDocument {
  const OrderDocument({
    required this.orderNo,
    required this.customerNo,
    required this.customerName,
    required this.lines,
    this.isZebra = false,
    this.orderDate,
    this.invoiceNo,
    this.invoiceDate,
    this.paymentMethod,
    this.trnNo,
    this.customerAddress,
    this.customerZone,
    this.customerCountry,
    this.customerPhone,
    this.currencyCode,
    this.balance,
    this.lastPaymentAmount,
    this.lastPaymentDate,
    this.note,
  });

  final String orderNo;
  final String customerNo;
  final String customerName;
  final List<OrderDocumentLine> lines;

  /// Selects the Zebra layout: the "Zebra Sales Quotation" title and the
  /// Length/Width columns.
  final bool isZebra;

  final DateTime? orderDate;

  /// Printed in the INVOICE NO./INVOICE DATE rows. Both null for an order
  /// the backend has not invoiced in its response — the rows are then
  /// omitted rather than printed empty.
  final String? invoiceNo;
  final DateTime? invoiceDate;

  /// e.g. "CASH ONLY". Null until the backend returns it.
  final String? paymentMethod;

  /// Tax registration number. Null until the backend returns it.
  final String? trnNo;

  final String? customerAddress;
  final String? customerZone;
  final String? customerCountry;
  final String? customerPhone;

  /// Currency for every monetary figure in this document, when known.
  /// Null prints bare amounts — never a guessed "$" (matching
  /// `formatCurrencyOrUnknown`'s rule for the rest of the app).
  final String? currencyCode;

  /// The customer's account balance and last payment, from the
  /// customer-details snapshot. Null when that snapshot was unavailable,
  /// which omits the block rather than printing a zero that would read as
  /// a settled account.
  final double? balance;
  final double? lastPaymentAmount;
  final DateTime? lastPaymentDate;

  final String? note;

  double get totalQuantity =>
      lines.fold(0, (sum, line) => sum + line.quantity);

  double get totalAmount => lines.fold(0, (sum, line) => sum + line.amount);

  double get totalDiscount =>
      lines.fold(0, (sum, line) => sum + (line.discountAmount ?? 0));

  double get netAmount =>
      lines.fold(0, (sum, line) => sum + line.amountAfterDiscount);
}
