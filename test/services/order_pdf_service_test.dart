import 'package:anc_fabrics/models/order_document.dart';
import 'package:anc_fabrics/services/order_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

OrderDocument _document({
  bool isZebra = false,
  String? invoiceNo,
  DateTime? invoiceDate,
  String? paymentMethod,
  String? trnNo,
  String? customerZone,
  double? balance,
  double? lastPaymentAmount,
  DateTime? lastPaymentDate,
  String? currencyCode = 'USD',
  List<OrderDocumentLine>? lines,
}) {
  return OrderDocument(
    orderNo: isZebra ? 'ZR-66713' : 'SO-351403',
    customerNo: isZebra ? 'CLNT-04779' : 'CLNT-00801',
    customerName: 'Khaled Badoura',
    isZebra: isZebra,
    orderDate: DateTime(2026, 8, 10),
    invoiceNo: invoiceNo,
    invoiceDate: invoiceDate,
    paymentMethod: paymentMethod,
    trnNo: trnNo,
    customerZone: customerZone,
    customerCountry: 'Lebanon',
    customerPhone: '76-050466',
    currencyCode: currencyCode,
    balance: balance,
    lastPaymentAmount: lastPaymentAmount,
    lastPaymentDate: lastPaymentDate,
    lines:
        lines ??
        const [
          OrderDocumentLine(
            description: 'Delivery Charge',
            quantity: 1,
            unitPrice: 0.26,
            amount: 0.26,
          ),
          OrderDocumentLine(
            description: '1213 02',
            quantity: 2,
            unitOfMeasureCode: 'MT',
            unitPrice: 6.50,
            amount: 13.00,
          ),
        ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalOrderPdfService service;

  // Uncompressed so the document's own text is readable in the bytes
  // below — the same technique account_statement_exporter_test uses.
  setUp(() => service = LocalOrderPdfService(compress: false));

  test('Produces a real PDF document', () async {
    final bytes = await service.generate(_document());

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('A standard order prints the Sales Quotation form', () async {
    final text = String.fromCharCodes(await service.generate(_document()));

    expect(text, contains('(Sales)'));
    expect(text, contains('(Quotation)'));
    expect(text, isNot(contains('(Zebra)')));
    expect(text, contains('(CLNT-00801)'));
    expect(text, contains('(SO-351403)'));
    expect(text, contains('(10/08/2026)'));
    // Delivery Charge 0.26 + 13.00 of fabric.
    expect(text, contains('(13.26)'));
  });

  test('A Zebra order prints the Zebra form, with its dimensions', () async {
    final text = String.fromCharCodes(
      await service.generate(
        _document(
          isZebra: true,
          lines: const [
            OrderDocumentLine(
              description: 'ROLLER 8010 33',
              quantity: 2.268,
              unitOfMeasureCode: 'M2',
              unitPrice: 9.00,
              amount: 20.41,
              length: 2.10,
              width: 1.08,
            ),
          ],
        ),
      ),
    );

    expect(text, contains('(Zebra)'));
    expect(text, contains('(Length)'));
    expect(text, contains('(Width)'));
    expect(text, contains('(2.10)'));
    expect(text, contains('(1.08)'));
    expect(text, contains('(ZR-66713)'));
  });

  test('A standard order prints no Length/Width columns at all', () async {
    final text = String.fromCharCodes(await service.generate(_document()));

    expect(text, isNot(contains('(Length)')));
    expect(text, isNot(contains('(Width)')));
  });

  test('Fields the backend does not return are omitted, never invented', () async {
    final text = String.fromCharCodes(await service.generate(_document()));

    expect(text, isNot(contains('(INVOICE)')));
    expect(text, isNot(contains('(TRN)')));
    expect(text, isNot(contains('(Payment)')));
    expect(text, isNot(contains('(Zone)')));
  });

  test('Those same fields print once they are supplied', () async {
    final text = String.fromCharCodes(
      await service.generate(
        _document(
          invoiceNo: 'SN-311887',
          invoiceDate: DateTime(2026, 8, 11),
          paymentMethod: 'CASH ONLY',
          trnNo: '100123456700003',
          customerZone: 'Saida',
        ),
      ),
    );

    expect(text, contains('(SN-311887)'));
    expect(text, contains('(11/08/2026)'));
    expect(text, contains('(CASH)'));
    expect(text, contains('(100123456700003)'));
    expect(text, contains('(Saida)'));
  });

  test('The account block prints balance and last payment when known', () async {
    final text = String.fromCharCodes(
      await service.generate(
        _document(
          balance: 24.37,
          lastPaymentAmount: -12.00,
          lastPaymentDate: DateTime(2026, 8, 7),
        ),
      ),
    );

    expect(text, contains('(Balance)'));
    expect(text, contains('(USD)'));
    expect(text, contains('(24.37)'));
    expect(text, contains('(07/08/2026)'));
    expect(text, contains('(-12.00)'));
  });

  test(
    'No customer-details snapshot omits the account block rather than '
    'printing a zero balance',
    () async {
      final text = String.fromCharCodes(await service.generate(_document()));

      expect(text, isNot(contains('(Balance)')));
      expect(text, isNot(contains('(Payment)')));
    },
  );

  test('An unknown currency prints bare amounts, never a guessed symbol', () async {
    final text = String.fromCharCodes(
      await service.generate(_document(currencyCode: null, balance: 24.37)),
    );

    expect(text, contains('(24.37)'));
    expect(text, isNot(contains(r'($24.37)')));
    expect(text, isNot(contains('(USD)')));
  });

  test('Totals are summed from the lines, not taken on trust', () async {
    final document = _document(
      lines: const [
        OrderDocumentLine(
          description: 'A',
          quantity: 2,
          unitPrice: 10,
          amount: 20,
          discountAmount: 5,
        ),
        OrderDocumentLine(
          description: 'B',
          quantity: 3,
          unitPrice: 10,
          amount: 30,
        ),
      ],
    );

    expect(document.totalQuantity, 5);
    expect(document.totalAmount, 50);
    expect(document.totalDiscount, 5);
    expect(document.netAmount, 45);

    final text = String.fromCharCodes(await service.generate(document));
    expect(text, contains('(45.00)'));
  });

  test('Thousands are separated the way the printed form does', () async {
    final text = String.fromCharCodes(
      await service.generate(
        _document(
          lines: const [
            OrderDocumentLine(
              description: 'Bulk',
              quantity: 1000,
              unitPrice: 1234.5,
              amount: 1234567.89,
            ),
          ],
        ),
      ),
    );

    expect(text, contains('(1,234,567.89)'));
  });

  test('The Delivery Note slip is included', () async {
    final text = String.fromCharCodes(await service.generate(_document()));

    expect(text, contains('(Delivery)'));
    expect(text, contains('(Note)'));
    expect(text, contains('(Contact)'));
    expect(text, contains('(76-050466)'));
  });

  group('Arabic', () {
    test('An Arabic customer name embeds the Arabic font', () async {
      final bytes = await service.generate(
        OrderDocument(
          orderNo: 'SO-339392',
          customerNo: 'CLNT-04677',
          customerName: 'ياسر خزيم',
          customerAddress: 'بيروت B, BEIRUT B',
          customerCountry: 'Lebanon',
          lines: const [
            OrderDocumentLine(
              description: 'قماش هاواي',
              quantity: 18,
              unitOfMeasureCode: 'MT',
              unitPrice: 7.5,
              amount: 135,
            ),
          ],
        ),
      );
      final text = String.fromCharCodes(bytes);

      // The built-in base fonts carry no Arabic glyphs, so the bundled TTF
      // must actually be embedded for the name to render at all.
      expect(text, contains('NotoNaskhArabic'));
      expect(bytes, isNotEmpty);
    });

    test('Latin-only documents still render without the Arabic font', () async {
      final text = String.fromCharCodes(await service.generate(_document()));

      expect(text, contains('(Sales)'));
      expect(text, contains('(CLNT-00801)'));
    });
  });
}
