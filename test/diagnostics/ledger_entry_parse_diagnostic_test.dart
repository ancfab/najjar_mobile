// TEMPORARY DIAGNOSTIC — investigates the live Current Balance
// "Couldn't load data right now" failure. Exercises the real
// LedgerEntry.fromJson parser (no changes to production code) against
// representative live-API row shapes. Delete this file once the
// investigation is closed out.

import 'package:flutter_test/flutter_test.dart';
import 'package:anc_fabrics/models/business_central/ledger_entry.dart';

Map<String, dynamic> _validRow({Object? documentType = 'Invoice'}) => {
  'Entry_No': 1,
  'Posting_Date': '2026-01-01',
  'Document_Type': documentType,
  'Document_No': 'INV-1',
  'Customer_No': 'C-1',
  'Customer_Name': 'Test Customer',
  'Currency_Code': 'AED',
  'Amount': 100.0,
  'Remaining_Amount': 100.0,
  'Due_Date': '2026-02-01',
  'Open': true,
};

void _tryParse(String label, Map<String, dynamic> json) {
  try {
    final entry = LedgerEntry.fromJson(json);
    // ignore: avoid_print
    print('[PARSE DIAGNOSTIC] $label -> SUCCESS: $entry');
  } catch (error) {
    // ignore: avoid_print
    print('[PARSE DIAGNOSTIC] $label -> THROWS ${error.runtimeType}: $error');
  }
}

void main() {
  test('diagnostic: normal row parses', () {
    _tryParse('normal row', _validRow());
  });

  test('diagnostic: blank Document_Type ("")', () {
    _tryParse('blank Document_Type', _validRow(documentType: ''));
  });

  test('diagnostic: null Document_Type', () {
    _tryParse('null Document_Type', _validRow(documentType: null));
  });

  test('diagnostic: missing Document_Type key entirely', () {
    final row = _validRow()..remove('Document_Type');
    _tryParse('missing Document_Type key', row);
  });

  test('diagnostic: blank Currency_Code ("")', () {
    final row = {..._validRow(), 'Currency_Code': ''};
    _tryParse('blank Currency_Code', row);
  });

  test('diagnostic: closed row + blank Document_Type', () {
    final row = {..._validRow(documentType: ''), 'Open': false};
    _tryParse('closed + blank Document_Type', row);
  });

  test('diagnostic: empty object {}', () {
    _tryParse('empty object', <String, dynamic>{});
  });
}
