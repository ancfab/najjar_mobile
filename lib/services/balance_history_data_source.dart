import '../models/balance_history_point.dart';
import '../models/business_central/ledger_entry.dart';
import 'current_balance_service.dart';
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
  LedgerBalanceHistoryDataSource({LedgerEntriesService? ledgerEntriesService})
    : _ledgerEntriesService = ledgerEntriesService ?? LedgerEntriesService();

  final LedgerEntriesService _ledgerEntriesService;

  @override
  Future<BalanceHistoryData> fetchBalanceHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    await _ledgerEntriesService.loadAllPages();
    final allEntries = _ledgerEntriesService.entries;

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

    // Reuses the exact same pure function/rule CurrentBalanceService uses —
    // never a second, competing balance calculation.
    final currentBalance = computeCurrentBalance(allEntries).amount;

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

  /// Closes the underlying [LedgerEntriesService]'s HTTP client, but only
  /// when this instance created its own (a caller-supplied
  /// [LedgerEntriesService] is left for the caller to manage).
  void close() => _ledgerEntriesService.close();
}
