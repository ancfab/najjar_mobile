// Fake QuickHistoryDataSource for AccountBalanceScreen tests: returns
// canned rows or throws a canned exception, without exercising real HTTP or
// secure storage.

import 'package:anc_fabrics/models/account_transaction.dart';
import 'package:anc_fabrics/services/ledger_entry_presentation_adapter.dart';

class FakeQuickHistoryDataSource implements QuickHistoryDataSource {
  FakeQuickHistoryDataSource({
    List<AccountTransaction>? rows,
    this.error,
    this.pendingFuture,
  }) : rows = rows ?? const [];

  final List<AccountTransaction> rows;

  /// When set, thrown from [fetchQuickHistoryRows] instead of returning
  /// [rows].
  final Object? error;

  /// When set, awaited instead of resolving immediately — lets a test
  /// observe the loading state before controlling exactly when/how the
  /// call completes.
  final Future<List<AccountTransaction>>? pendingFuture;

  int callCount = 0;

  @override
  Future<List<AccountTransaction>> fetchQuickHistoryRows() async {
    callCount++;
    if (pendingFuture != null) return pendingFuture!;
    if (error != null) throw error!;
    return rows;
  }
}
