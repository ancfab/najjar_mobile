import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/account_statement_data.dart';
import '../models/account_transaction.dart';
import '../models/balance_history_range.dart';
import '../utils/currency.dart';
import '../utils/date_time_format.dart';
import '../utils/filename.dart';

/// Prepares and hands off the Account Balance screen's exportable
/// statement PDF. A single seam (rather than the separate generate/print/
/// save steps of the Invoice Details flow) since Export PDF is one action
/// that opens the native share/save/print sheet directly.
abstract class AccountStatementExporter {
  Future<void> export(AccountStatementData data);
}

// TODO(api): Confirm whether the production account statement must be generated
// by the backend. Replace or reconcile this local PDF with the authoritative
// statement endpoint once its contract is available.
/// Generates the account statement PDF entirely on-device from currently
/// available Account Balance screen data, then opens the native
/// Android/iOS share sheet so the user can save, print, or share it.
class LocalAccountStatementPdfExporter implements AccountStatementExporter {
  const LocalAccountStatementPdfExporter();

  @override
  Future<void> export(AccountStatementData data) async {
    final bytes = await buildAccountStatementPdfBytes(data);
    await Printing.sharePdf(
      bytes: bytes,
      filename: accountStatementPdfFilename(data.generatedAt),
    );
  }
}

/// Builds the account statement PDF's raw bytes from [data]. Split out from
/// [LocalAccountStatementPdfExporter.export] so the document's contents can
/// be unit-tested directly without invoking the native share sheet.
///
/// Uncompressed (`compress: false`): this is a small, text-only document,
/// so the simpler, directly-inspectable output is worth more than the
/// smaller file size compression would give.
Future<Uint8List> buildAccountStatementPdfBytes(
  AccountStatementData data,
) async {
  final doc = pw.Document(compress: false);

  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        _buildHeader(data),
        pw.SizedBox(height: 20),
        _buildBalanceSection(data),
        pw.SizedBox(height: 16),
        _buildCreditSection(data),
        pw.SizedBox(height: 16),
        _buildHistoryRangeSection(data),
        if (data.quickHistory.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          _buildQuickHistorySection(data),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _buildHeader(AccountStatementData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Indigo Loom',
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Account Statement',
        style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 4),
      pw.Text('Generated: ${formatDateOnly(data.generatedAt)}'),
    ],
  );
}

pw.Widget _buildBalanceSection(AccountStatementData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('GLOBAL ACCOUNT BALANCE'),
      pw.SizedBox(height: 4),
      pw.Text(
        formatCurrencyOrUnknown(
          data.customerBalance,
          currencyCode: data.currencyCode,
        ),
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

pw.Widget _buildCreditSection(AccountStatementData data) {
  final credit = data.creditUtilization;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('CREDIT UTILIZATION'),
      pw.SizedBox(height: 4),
      _statRow('Available Credit', credit.availableCredit, data.currencyCode),
      _statRow('Used Credit', credit.usedCredit, data.currencyCode),
    ],
  );
}

pw.Widget _buildHistoryRangeSection(AccountStatementData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('BALANCE HISTORY RANGE'),
      pw.SizedBox(height: 4),
      pw.Text(data.selectedRange.label),
    ],
  );
}

pw.Widget _buildQuickHistorySection(AccountStatementData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('QUICK HISTORY'),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: const ['Date', 'Transaction', 'Amount'],
        data: [
          for (final txn in data.quickHistory)
            [
              formatDateOnly(txn.occurredAt),
              txn.label,
              _formatTransactionAmount(txn),
            ],
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {2: pw.Alignment.centerRight},
      ),
    ],
  );
}

/// Formats [txn]'s amount for the statement's Quick History table, matching
/// the currency presentation used on the Quick History card and Transaction
/// Details screen: transactions carrying a currency code (e.g. Business
/// Central ledger entries) render with that code via [formatCurrency],
/// while legacy transactions with no currency code keep the existing signed
/// dollar format from [formatSignedCurrency].
String _formatTransactionAmount(AccountTransaction txn) {
  final currencyCode = txn.currencyCode;
  if (currencyCode != null && currencyCode.isNotEmpty) {
    return formatCurrency(txn.amount, currencyCode: currencyCode);
  }
  return formatSignedCurrency(txn.amount);
}

pw.Widget _statRow(String label, double amount, String? currencyCode) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label),
        pw.Text(formatCurrencyOrUnknown(amount, currencyCode: currencyCode)),
      ],
    ),
  );
}

pw.Widget _sectionLabel(String label) {
  return pw.Text(
    label,
    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  );
}
