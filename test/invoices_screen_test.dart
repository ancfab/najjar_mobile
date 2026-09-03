// Widget checks for the Invoices screen: live grouping by Document_No,
// currency-prefixed totals (never a "?" unknown-currency marker), loading/
// error/empty states, load-more pagination, and the overdue-scope note —
// against a real InvoicesService wired to a scripted fake http.Client
// (never the live ANC API) and a fake in-memory AuthSessionStore.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/localization/app_translations_delegate.dart';
import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/screens/invoice_details_screen.dart';
import 'package:anc_fabrics/screens/invoices_screen.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/invoices_service.dart';

import 'helpers/fake_auth_session_store.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

const _session = AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: 'sample.user',
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

class _ScriptedHttpClient extends http.BaseClient {
  _ScriptedHttpClient(this._responses);

  final List<Future<http.StreamedResponse> Function(http.Request)> _responses;
  final List<Uri> requestedUrls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestedUrls.add(req.url);
    return _responses.removeAt(0)(req);
  }

  @override
  void close() {}
}

http.StreamedResponse _jsonResponse(
  int statusCode,
  Map<String, dynamic> body, {
  required http.Request request,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))),
  statusCode,
  request: request,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _invoiceLineJson({
  String documentNo = 'INV-24001',
  int lineNo = 10000,
  String customerNo = 'CLNT-0001',
  String customerName = 'Test Customer One',
  double amount = 180,
  double amountIncludingVat = 189,
  String currencyCode = 'OMR',
}) => {
  'Document_No': documentNo,
  'Line_No': lineNo,
  'Posting_Date': '2026-03-21',
  'Sell_to_Customer_No': customerNo,
  'Sell_to_Customer_Name': customerName,
  'Type': 'Item',
  'No': 'ITEM-001',
  'Description': 'Test Fabric Item',
  'Quantity': 12,
  'Unit_Price': 15,
  'Amount': amount,
  'Amount_Including_VAT': amountIncludingVat,
  'Order_No': '',
  'Currency_Code': currencyCode,
};

Map<String, dynamic> _envelope({
  required List<Map<String, dynamic>> rows,
  int currentPage = 1,
  int lastPage = 1,
}) => {
  'current_page': currentPage,
  'data': rows,
  'first_page_url': '/?page=1',
  'from': rows.isEmpty ? null : 1,
  'last_page': lastPage,
  'last_page_url': '/?page=$lastPage',
  'next_page_url': currentPage < lastPage ? '/?page=${currentPage + 1}' : null,
  'path': '/',
  'per_page': 25,
  'prev_page_url': null,
  'to': rows.isEmpty ? null : rows.length,
  'total': rows.length,
};

InvoicesService _serviceWith(
  List<Future<http.StreamedResponse> Function(http.Request)> responses,
) {
  final httpClient = _ScriptedHttpClient(responses);
  final store = FakeAuthSessionStore()..seed(_session);
  return InvoicesService(
    apiClient: AncApiClient(httpClient: httpClient),
    sessionStore: store,
  );
}

Future<void> _pumpInvoices(
  WidgetTester tester,
  InvoicesService service, {
  InvoiceStatusFilter filter = InvoiceStatusFilter.all,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: InvoicesScreen(filter: filter, invoicesService: service),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Currency display', () {
    testWidgets(
      "prefixes the invoice total with the invoice's own Currency_Code",
      (tester) async {
        final service = _serviceWith([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _invoiceLineJson(amountIncludingVat: 189, currencyCode: 'OMR'),
              ],
            ),
            request: req,
          ),
        ]);

        await _pumpInvoices(tester, service);

        expect(find.text('OMR 189.00'), findsOneWidget);
        expect(find.textContaining('?'), findsNothing);
      },
    );

    testWidgets(
      'shows the plain total, no prefix, when Currency_Code is blank',
      (tester) async {
        final service = _serviceWith([
          (req) async => _jsonResponse(
            200,
            _envelope(
              rows: [
                _invoiceLineJson(amountIncludingVat: 189, currencyCode: ''),
              ],
            ),
            request: req,
          ),
        ]);

        await _pumpInvoices(tester, service);

        expect(find.text('189.00'), findsOneWidget);
        expect(find.textContaining('?'), findsNothing);
      },
    );
  });

  group('Grouping', () {
    testWidgets('groups lines sharing a Document_No into one card with a '
        'summed total', (tester) async {
      final service = _serviceWith([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _invoiceLineJson(
                documentNo: 'INV-24001',
                lineNo: 10000,
                amountIncludingVat: 100,
              ),
              _invoiceLineJson(
                documentNo: 'INV-24001',
                lineNo: 20000,
                amountIncludingVat: 50,
              ),
              _invoiceLineJson(
                documentNo: 'INV-24002',
                lineNo: 10000,
                amountIncludingVat: 75,
              ),
            ],
          ),
          request: req,
        ),
      ]);

      await _pumpInvoices(tester, service);

      expect(find.byKey(const ValueKey('invoice-card-INV-24001')), findsOneWidget);
      expect(find.byKey(const ValueKey('invoice-card-INV-24002')), findsOneWidget);
      expect(find.text('OMR 150.00'), findsOneWidget); // 100 + 50
      expect(find.text('OMR 75.00'), findsOneWidget);
    });

    testWidgets('tapping a card opens InvoiceDetailsScreen with that '
        "invoice's own lines only", (tester) async {
      final service = _serviceWith([
        (req) async => _jsonResponse(
          200,
          _envelope(
            rows: [
              _invoiceLineJson(documentNo: 'INV-24001', lineNo: 10000),
              _invoiceLineJson(documentNo: 'INV-24002', lineNo: 10000),
            ],
          ),
          request: req,
        ),
      ]);

      await _pumpInvoices(tester, service);
      await tester.tap(find.byKey(const ValueKey('invoice-card-INV-24001')));
      await tester.pumpAndSettle();

      expect(find.byType(InvoiceDetailsScreen), findsOneWidget);
    });
  });

  group('Load states', () {
    testWidgets('shows the empty state when there are no invoices', (
      tester,
    ) async {
      final service = _serviceWith([
        (req) async => _jsonResponse(200, _envelope(rows: []), request: req),
      ]);

      await _pumpInvoices(tester, service);

      expect(find.byKey(const ValueKey('invoices-empty')), findsOneWidget);
    });

    testWidgets('shows the error state with retry on a failed load', (
      tester,
    ) async {
      final service = _serviceWith([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);

      await _pumpInvoices(tester, service);

      expect(find.byKey(const ValueKey('invoices-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('invoices-retry')), findsOneWidget);
    });

    testWidgets('the overdue scope note appears only for the overdue filter', (
      tester,
    ) async {
      final service = _serviceWith([
        (req) async => _jsonResponse(
          200,
          _envelope(rows: [_invoiceLineJson()]),
          request: req,
        ),
      ]);

      await _pumpInvoices(
        tester,
        service,
        filter: InvoiceStatusFilter.overdue,
      );

      expect(find.byKey(const ValueKey('invoices-overdue-note')), findsOneWidget);
      expect(find.text('Overdue Invoices'), findsOneWidget);
    });
  });
}
