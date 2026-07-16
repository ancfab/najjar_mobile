// Fake AccountStatementExporter for tests that exercise the Export PDF flow
// without generating a real PDF or opening the native share sheet.

import 'dart:async';

import 'package:anc_fabrics/models/account_statement_data.dart';
import 'package:anc_fabrics/services/account_statement_exporter.dart';

class FakeAccountStatementExporter implements AccountStatementExporter {
  FakeAccountStatementExporter({this.error, this.pending});

  /// Exception to throw from [export], if any. Ignored when [pending] is
  /// set.
  Object? error;

  /// When set, `export` awaits this instead of resolving immediately — lets
  /// tests hold the export flow "in flight" to observe the loading state
  /// and the duplicate-tap guard.
  final Completer<void>? pending;

  final List<AccountStatementData> exportedData = [];

  @override
  Future<void> export(AccountStatementData data) async {
    exportedData.add(data);
    if (pending != null) return pending!.future;
    if (error != null) throw error!;
  }
}
