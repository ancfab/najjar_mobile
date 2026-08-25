import 'package:flutter/foundation.dart';

import '../models/business_central/ledger_entry.dart';
import 'ledger_entries_service.dart';

/// Confirmed Business Central `Document_Type` values that contribute to
/// Current Balance — this exact set only. Any other value (including one
/// this app has simply never seen before) is excluded, never guessed at.
const Set<String> kCurrentBalanceRelevantDocumentTypes = {
  'Invoice',
  'Payment',
  'Credit Memo',
  'Refund',
  'Finance Charge Memo',
  'Reminder',
};

/// One customer's Current Balance, derived from their open ledger entries.
///
/// [currencyCode] is the single nonblank `Currency_Code` shared by every
/// entry that contributed to [amount], or `null` when no contributing entry
/// had a nonblank currency code — including when there were no contributing
/// entries at all. Callers must render `null` as an explicit "unknown
/// currency" indicator, never default it to USD/"$" (see
/// `formatCurrencyOrUnknown`).
class CurrentBalanceAmount {
  const CurrentBalanceAmount({
    required this.amount,
    required this.currencyCode,
  });

  final double amount;
  final String? currencyCode;
}

/// Thrown by [computeCurrentBalance] when the entries contributing to the
/// balance report more than one distinct nonblank `Currency_Code`. ANC
/// guarantees one currency per customer, so this signals an inconsistent or
/// malformed response — never something to combine silently or pick one of.
class CurrentBalanceInconsistentCurrencyException implements Exception {
  const CurrentBalanceInconsistentCurrencyException(this.currencyCodes);

  /// The distinct nonblank currency codes found — for diagnostics only,
  /// never shown to the user (see `HomeScreen`'s generic error copy).
  final Set<String> currencyCodes;

  @override
  String toString() =>
      'CurrentBalanceInconsistentCurrencyException($currencyCodes)';
}

/// Computes Current Balance from already-fetched ledger [entries], per the
/// confirmed rule: sum `Remaining_Amount` (sign preserved exactly — never
/// `Amount`, never `Due_Date`) over every entry where `Open == true` and
/// `Document_Type` is one of [kCurrentBalanceRelevantDocumentTypes]. Pure —
/// performs no I/O and never pages itself; see [CurrentBalanceService] for
/// the full-pagination fetch this is applied to.
///
/// Zero contributing entries (including an empty [entries] list) returns a
/// zero balance with a `null` [CurrentBalanceAmount.currencyCode] — never
/// mock data and never a guessed currency.
CurrentBalanceAmount computeCurrentBalance(List<LedgerEntry> entries) {
  var total = 0.0;
  final currencyCodes = <String>{};

  for (final entry in entries) {
    if (!entry.isOpen) continue;
    if (!kCurrentBalanceRelevantDocumentTypes.contains(entry.documentType)) {
      continue;
    }
    total += entry.remainingAmount;
    final code = entry.currencyCode.trim();
    if (code.isNotEmpty) currencyCodes.add(code);
  }

  if (currencyCodes.length > 1) {
    throw CurrentBalanceInconsistentCurrencyException(currencyCodes);
  }

  return CurrentBalanceAmount(
    amount: total,
    currencyCode: currencyCodes.isEmpty ? null : currencyCodes.single,
  );
}

/// Purpose: Loads every page of the authenticated customer's Business
/// Central ledger entries and reduces them to a Current Balance, for the
/// Home screen's Current Balance card.
///
/// Reuses [LedgerEntriesService] for transport, pagination, `Entry_No`
/// dedup, and Business Central error mapping rather than duplicating any of
/// it — this class only drives that engine through every page and then
/// applies [computeCurrentBalance]. Because [LedgerEntriesService.entries]
/// is already deduplicated by `Entry_No`, a boundary row repeated across two
/// pages is never double-counted here.
///
/// [maxPages] is a hard defensive cap (not a business rule) against a
/// pagination loop — e.g. a backend bug where `next_page_url` never becomes
/// `null` — comfortably above any real customer's ledger size.
class CurrentBalanceService {
  CurrentBalanceService({
    LedgerEntriesService? ledgerEntriesService,
    this.maxPages = 500,
  }) : _ledgerEntriesService = ledgerEntriesService ?? LedgerEntriesService();

  final LedgerEntriesService _ledgerEntriesService;
  final int maxPages;

  /// Fetches every page of ledger entries (starting from page 1) and
  /// returns the resulting Current Balance. Throws
  /// `SessionExpiredException`/`BusinessCentralFailureException` (via
  /// [LedgerEntriesService]) or [CurrentBalanceInconsistentCurrencyException]
  /// on failure — a failure at any page (including a mid-pagination one)
  /// discards nothing locally but never returns a partial balance either;
  /// [LedgerEntriesService] leaves its already-loaded rows untouched on a
  /// load-more failure, but this method still throws rather than reducing
  /// them, since a partial page set is not a confirmed complete balance.
  Future<CurrentBalanceAmount> fetchCurrentBalance() async {
    // TEMPORARY DIAGNOSTIC — Current Balance investigation. Remove once
    // diagnosed.
    debugPrint('[CURRENT BALANCE] load started');
    await _ledgerEntriesService.loadFirstPage();
    var pagesLoaded = 1;
    while (_ledgerEntriesService.hasNextPage && pagesLoaded < maxPages) {
      await _ledgerEntriesService.loadNextPage();
      pagesLoaded++;
    }
    debugPrint(
      '[CURRENT BALANCE] all pages loaded: $pagesLoaded, '
      'total entries: ${_ledgerEntriesService.entries.length}',
    );
    final result = computeCurrentBalance(_ledgerEntriesService.entries);
    debugPrint('[CURRENT BALANCE] calculation succeeded');
    return result;
  }

  /// Closes the underlying [LedgerEntriesService]'s HTTP client, but only
  /// when this instance created its own (a caller-supplied
  /// [LedgerEntriesService] is left for the caller to manage).
  void close() => _ledgerEntriesService.close();
}
