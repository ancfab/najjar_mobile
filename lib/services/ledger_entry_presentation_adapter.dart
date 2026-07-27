import '../models/account_transaction.dart';
import '../models/business_central/ledger_entry.dart';
import 'ledger_entries_service.dart';

/// Number of ledger-derived rows shown in the Quick History card — kept
/// equal to the number of rows the previous mock data always showed, since
/// no approved full Account Statement / ledger list screen exists yet to
/// send "See all" to (see `QuickHistoryDataSource`).
const int kQuickHistoryVisibleRowCount = 3;

/// Maps one [LedgerEntry] onto the existing Quick History presentation
/// model.
///
/// Deliberately renders [AccountTransactionType.neutral] and
/// [AccountTransactionCategory.ledgerEntry]: the ledger-entries API contract
/// does not define whether a positive or negative `Amount` means a credit
/// or a debit, so this never guesses at a color or a "Credit"/"Debit" label
/// — see `AccountTransactionType.neutral`'s doc comment.
///
/// Only maps fields the endpoint actually provides — this must never
/// derive a running balance, a credit/debit label, or anything else the
/// ledger-entries response doesn't state outright.
AccountTransaction adaptLedgerEntryToAccountTransaction(LedgerEntry entry) {
  return AccountTransaction(
    id: 'ledger-entry-${entry.entryNo}',
    label: '${entry.documentType} ${entry.documentNo}'.trim(),
    amount: entry.amount,
    type: AccountTransactionType.neutral,
    occurredAt: entry.postingDate,
    category: AccountTransactionCategory.ledgerEntry,
    reference: entry.documentNo,
    currencyCode: entry.currencyCode,
  );
}

/// Purpose: The seam `AccountBalanceScreen` depends on for Quick History
/// data — abstract so widget tests can inject a fake instead of exercising
/// real HTTP/secure-storage, matching the existing `AccountBalanceService`/
/// `AccountStatementExporter` injectable-service convention.
abstract class QuickHistoryDataSource {
  /// Returns up to [kQuickHistoryVisibleRowCount] rows for display. Throws
  /// `SessionExpiredException` or `BusinessCentralFailureException` (see
  /// `business_central_error_mapper.dart`) on failure — never a raw
  /// [AncApiException] or platform exception.
  Future<List<AccountTransaction>> fetchQuickHistoryRows();
}

/// Default [QuickHistoryDataSource]: loads page 1 of the ledger-entries
/// endpoint via [LedgerEntriesService] and adapts the first
/// [kQuickHistoryVisibleRowCount] rows for display.
///
/// The full paginated [LedgerEntriesService] underneath already supports
/// loading further pages — this data source only surfaces page 1's first
/// few rows because no approved infinite-scroll Account Statement UI exists
/// yet to show the rest (see the task's Phase 1 scope note).
class LedgerQuickHistoryDataSource implements QuickHistoryDataSource {
  LedgerQuickHistoryDataSource({LedgerEntriesService? ledgerEntriesService})
    : _ledgerEntriesService = ledgerEntriesService ?? LedgerEntriesService();

  final LedgerEntriesService _ledgerEntriesService;

  @override
  Future<List<AccountTransaction>> fetchQuickHistoryRows() async {
    await _ledgerEntriesService.loadFirstPage();
    return [
      for (final entry in _ledgerEntriesService.entries.take(
        kQuickHistoryVisibleRowCount,
      ))
        adaptLedgerEntryToAccountTransaction(entry),
    ];
  }
}
