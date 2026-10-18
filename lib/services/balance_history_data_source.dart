import '../config/api_config.dart';
import '../models/balance_history_point.dart';
import '../models/business_central/customer_details.dart';
import '../models/business_central/ledger_entry.dart';
import 'current_balance_service.dart';
import 'customer_details_service.dart';
import 'ledger_entries_service.dart';

/// Strips the time-of-day component so callers only ever compare calendar
/// dates — [LedgerEntry.postingDate] is already date-only (parsed from a
/// strict `yyyy-MM-dd` string, see `LedgerEntry._requireDateOnly`), but
/// [from]/[to] come from `showDatePicker`, whose returned `DateTime` is
/// date-only in the local time zone by contract. Normalizing both sides here
/// keeps the inclusive-boundary comparison correct even if either input ever
/// carried a non-midnight time component.
DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Result of [BalanceHistoryDataSource.fetchBalanceHistory]: the graph
/// points for the selected range (empty when [hasMultipleCurrencies] is
/// true, or when the range/history genuinely produces none). Balance
/// History is graph-only — the individual ledger transaction list lives on
/// Quick History (`QuickHistoryDataSource`/`LedgerQuickHistoryDataSource`),
/// not here.
class BalanceHistoryData {
  const BalanceHistoryData({
    required this.points,
    required this.currencyCode,
    required this.hasMultipleCurrencies,
  });

  /// Graph points, oldest first. Reflects only the confirmed
  /// balance-relevant `Document_Type`s (see
  /// `isCurrentBalanceRelevantDocumentType`) — the same rule Current Balance
  /// itself is confirmed to use — never the full unfiltered entry set.
  final List<BalanceHistoryPoint> points;

  /// The single currency every entry contributing to [points] shared, or
  /// `null` when they were all blank. Always `null` when
  /// [hasMultipleCurrencies] is true.
  final String? currencyCode;

  /// True when the balance-relevant entries span more than one distinct,
  /// nonblank `Currency_Code` — in which case summing them into a single
  /// balance series would be meaningless, so [points] is empty and the
  /// caller must show an explanatory state instead of a graph.
  final bool hasMultipleCurrencies;
}

/// Data seam for the Account Balance screen's Balance History section —
/// abstract so widget tests can inject a fake, matching the
/// `QuickHistoryDataSource`/`AccountBalanceService` injectable-service
/// convention.
abstract class BalanceHistoryDataSource {
  /// Returns the graph points for [from]..[to] inclusive (date-only
  /// comparison — see [LedgerBalanceHistoryDataSource]'s doc comment).
  /// Throws `SessionExpiredException`,
  /// `BusinessCentralFailureException`, or
  /// `CurrentBalanceInconsistentCurrencyException` on failure — never a raw
  /// `AncApiException` or platform exception, and never mock data.
  Future<BalanceHistoryData> fetchBalanceHistory({
    required DateTime from,
    required DateTime to,
  });
}

/// Default [BalanceHistoryDataSource]: loads every page of the
/// authenticated customer's Business Central ledger entries via
/// [LedgerEntriesService] (the same live pipeline `CurrentBalanceService`
/// and `LedgerQuickHistoryDataSource` already use) and reconstructs the real
/// historical account-balance series for the requested [from]/[to] range.
///
/// Filters/fetches locally rather than sending a date query parameter: the
/// ledger-entries endpoint's confirmed contract currently supports only
/// `page`/`per_page` — no `date_from`/`date_to`/`from`/`to` (or any other
/// date-range parameter) has ever been confirmed for this endpoint (unlike
/// `customer-details`, whose `date_from`/`date_to` are confirmed accepted
/// but confirmed *ineffective* — see `CustomerDetailsService`'s doc
/// comment). Sending an unconfirmed parameter name risks being silently
/// ignored by the backend the same way. This class must not gain a
/// date-filtered request until such a parameter is confirmed; when one is,
/// this is the one place to add it.
///
/// Deliberately fetches *every* page unfiltered (never scoped to [from]),
/// because reconstructing a historical balance as of [from] requires
/// summing every relevant entry's `Amount` between [from] and today — see
/// the reconstruction formula below.
///
/// ## Historical balance reconstruction
///
/// Neither `Amount` nor `Remaining_Amount` may be assumed to be the balance
/// movement without justification (see the class-level warning on
/// `LedgerEntry`): `Remaining_Amount` is a *present-day* figure — how much
/// of an entry is still outstanding *right now* — that changes over time as
/// later entries settle it, so it cannot represent what the balance was on
/// an arbitrary past date. `Amount` is the fixed value recorded at
/// `Posting_Date` and never mutates afterward, so it is the only field that
/// represents a dated movement.
///
/// There is no confirmed running/historical-balance field on this endpoint.
/// Instead, this reconstructs history backward from the one authoritative
/// anchor this app already has: [computeCurrentBalance] — the exact same
/// pure function `CurrentBalanceService` uses, called here on the same
/// already-fetched entries rather than duplicating a second network
/// round-trip. Restricting the walk to entries matching
/// [isCurrentBalanceRelevantDocumentType] (the same confirmed rule Current
/// Balance itself uses — named types plus Business Central's blank document
/// type) keeps the reconstruction consistent with that existing, confirmed
/// rule rather than inventing a new one.
///
/// Formula, for the confirmed-relevant entries only:
/// ```
/// openingBalance(from) = currentBalance - sum(Amount for entries with postingDate >= from)
/// balanceAfter(date)   = openingBalance + sum(Amount for entries in [from, date], date order)
/// ```
/// This is sign-convention-agnostic (it never guesses whether a positive
/// `Amount` is a credit or a debit) and is mathematically self-consistent
/// with [computeCurrentBalance]'s own confirmed formula under standard
/// Business Central customer-ledger settlement semantics (an entry's
/// `Remaining_Amount` is `Amount` minus whatever has been applied against it
/// by later entries, so summing `Amount` across an entry's full life —
/// open or closed — reproduces exactly what summing `Remaining_Amount`
/// across only currently-open entries gives today). This has not been
/// verified against a live response (no authenticated environment was
/// available), so it rests on that standard-BC-design assumption rather
/// than a live-confirmed contract — flagged here rather than presented as
/// fully proven.
///
/// One graph point is emitted per distinct calendar date that has
/// contributing activity within [from, to], holding the balance *after*
/// that date's entries — never one point per entry, to avoid dozens of
/// duplicate-date points. The first point is [from]'s opening balance
/// (`openingBalance(from)`) *unless* [from] itself has contributing
/// entries, in which case the first point is the resulting balance after
/// applying them (the opening balance is still used internally as that
/// day's starting point; it is just not plotted separately, to avoid two
/// points sharing the same date).
class LedgerBalanceHistoryDataSource implements BalanceHistoryDataSource {
  LedgerBalanceHistoryDataSource({
    LedgerEntriesService? ledgerEntriesService,
    CustomerDetailsService? customerDetailsService,
    this.maxPages = 20,
  }) : _ledgerEntriesService =
           ledgerEntriesService ??
           LedgerEntriesService(perPage: ApiConfig.businessCentralMaxPerPage),
       _customerDetailsService =
           customerDetailsService ?? CustomerDetailsService();

  final LedgerEntriesService _ledgerEntriesService;
  final CustomerDetailsService _customerDetailsService;

  /// Hard cap on how many ledger pages one graph will read. Only reached
  /// when a customer has thousands of entries inside the requested range;
  /// a defensive bound, not a business rule.
  final int maxPages;

  @override
  Future<BalanceHistoryData> fetchBalanceHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    // Started first so the balance request overlaps the ledger paging
    // rather than adding its own round trip on top. Its failure is captured
    // rather than thrown here: if the ledger walk below fails too, that is
    // the error the caller should see, and an abandoned request must not
    // surface as an unhandled error.
    Object? balanceError;
    final balanceRequest = _customerDetailsService
        .fetchCustomerDetails()
        .then<CustomerDetails?>(
          (details) => details,
          onError: (Object error) {
            balanceError = error;
            return null;
          },
        );

    final allEntries = await _loadEntriesFrom(_dateOnly(from));

    final details = await balanceRequest;
    if (details == null) throw balanceError!;
    final currentBalance = details.customerBalance;

    final fromDate = _dateOnly(from);
    final toDate = _dateOnly(to);

    // Only the confirmed balance-relevant entries feed the graph — the same
    // rule (named types plus Business Central's blank document type) Current
    // Balance itself is confirmed to use.
    final relevantAscending = [
      for (final entry in allEntries)
        if (isCurrentBalanceRelevantDocumentType(entry.documentType)) entry,
    ]..sort((a, b) => a.postingDate.compareTo(b.postingDate));

    final distinctCurrencies = {
      for (final entry in relevantAscending)
        if (entry.currencyCode.trim().isNotEmpty) entry.currencyCode.trim(),
    };

    if (distinctCurrencies.length > 1) {
      return BalanceHistoryData(
        points: const [],
        currencyCode: null,
        hasMultipleCurrencies: true,
      );
    }
    final currencyCode = distinctCurrencies.isEmpty
        ? null
        : distinctCurrencies.single;

    final futureFromOnwardsAmount = [
      for (final entry in relevantAscending)
        if (!_dateOnly(entry.postingDate).isBefore(fromDate)) entry.amount,
    ].fold(0.0, (sum, amount) => sum + amount);
    final openingBalance = currentBalance - futureFromOnwardsAmount;

    final relevantInRangeAscending = [
      for (final entry in relevantAscending)
        if (!_dateOnly(entry.postingDate).isBefore(fromDate) &&
            !_dateOnly(entry.postingDate).isAfter(toDate))
          entry,
    ];

    final points = <BalanceHistoryPoint>[];
    final startsWithOwnEntries =
        relevantInRangeAscending.isNotEmpty &&
        _dateOnly(relevantInRangeAscending.first.postingDate) == fromDate;
    if (!startsWithOwnEntries) {
      points.add(
        BalanceHistoryPoint(
          date: fromDate,
          balance: openingBalance,
          currencyCode: currencyCode,
        ),
      );
    }

    var running = openingBalance;
    DateTime? pendingDate;
    double? pendingBalance;
    for (final entry in relevantInRangeAscending) {
      final entryDate = _dateOnly(entry.postingDate);
      running += entry.amount;
      if (pendingDate == entryDate) {
        pendingBalance = running;
      } else {
        if (pendingDate != null) {
          points.add(
            BalanceHistoryPoint(
              date: pendingDate,
              balance: pendingBalance!,
              currencyCode: currencyCode,
            ),
          );
        }
        pendingDate = entryDate;
        pendingBalance = running;
      }
    }
    if (pendingDate != null) {
      points.add(
        BalanceHistoryPoint(
          date: pendingDate,
          balance: pendingBalance!,
          currencyCode: currencyCode,
        ),
      );
    }

    return BalanceHistoryData(
      points: points,
      currencyCode: currencyCode,
      hasMultipleCurrencies: false,
    );
  }

  /// Reads ledger pages until the graph has everything it needs: entries
  /// posted on or after [fromDate].
  ///
  /// The ledger endpoint has no date filter, so the range has to be found by
  /// paging. Entries come back newest first, so once a page holds nothing
  /// inside the range — and an earlier page did — the walk has passed the
  /// range and stops. That turns a default 30-day graph into one or two
  /// requests instead of a sweep of the customer's entire ledger, which is
  /// what made this screen take 10+ seconds.
  ///
  /// The stop is deliberately conditional on having already seen an
  /// in-range entry, so a backend that returned oldest-first would simply
  /// page through as before rather than stop on its first (old) page.
  Future<List<LedgerEntry>> _loadEntriesFrom(DateTime fromDate) async {
    await _ledgerEntriesService.loadFirstPage();
    var pagesLoaded = 1;
    var seenInRange = _containsFrom(_ledgerEntriesService.entries, fromDate);
    var scannedCount = _ledgerEntriesService.entries.length;

    while (_ledgerEntriesService.hasNextPage && pagesLoaded < maxPages) {
      await _ledgerEntriesService.loadNextPage();
      pagesLoaded++;

      final page = _ledgerEntriesService.entries.sublist(scannedCount);
      scannedCount = _ledgerEntriesService.entries.length;
      final pageHasInRange = _containsFrom(page, fromDate);
      if (seenInRange && !pageHasInRange) break;
      seenInRange = seenInRange || pageHasInRange;
    }

    return _ledgerEntriesService.entries;
  }

  bool _containsFrom(List<LedgerEntry> entries, DateTime fromDate) {
    for (final entry in entries) {
      if (!_dateOnly(entry.postingDate).isBefore(fromDate)) return true;
    }
    return false;
  }

  /// Closes the underlying services' HTTP clients, but only when this
  /// instance created its own (caller-supplied ones are left for the caller
  /// to manage).
  void close() {
    _ledgerEntriesService.close();
    _customerDetailsService.close();
  }
}
