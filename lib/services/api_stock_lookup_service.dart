import '../models/business_central/business_central_inventory_entry.dart';
import '../models/business_central/purchase_order_line.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';
import 'stock_lookup_service.dart';

/// Purpose: The production [StockLookupService] adapter. Resolves a scanned/
/// typed code — confirmed to be an exact Business Central `itemNo` (see this
/// library's other doc comment in `stock_lookup_service.dart`) — to
/// per-location open stock availability via `GET
/// /api/business-central/inventory?item_no=...`.
///
/// Responsibilities:
/// - Request only *filtered* inventory pages (`item_no` always set) at
///   `per_page: 100`, starting at page 1 and following `current_page`/
///   `last_page` — never `next_page_url`, which has been unsafe/incomplete
///   on every other Business Central list endpoint (see `InventoryService`'s
///   doc comment: observed as a bare `/?page=2` / `/`). This matches
///   `InventoryService`'s own established convention of trusting the
///   backend's numeric page fields (`hasNextPage => _currentPage < _lastPage`)
///   while never following its URLs.
/// - Validate that metadata before trusting it: each response's
///   `current_page` must be `>= 1`, `<= last_page`, exactly the page just
///   requested, and strictly greater than the previous response's
///   `current_page` (rejects a page number that regresses, repeats, or never
///   advances). Any violation — or reaching the defensive [_maxPages] bound
///   without ever reaching the last page — aborts the fetch as incomplete;
///   see [_fetchAllFilteredPages]. [lookup] then returns
///   [StockLookupUnexpectedFailure] rather than [StockLookupSuccess] built
///   from a truncated/partially-fetched row set.
/// - Keep only rows whose `itemNo` exactly matches the request and whose
///   `open` flag is `true`; sum `remainingQuantity` by
///   (`locationCode`, `unitOfMeasureCode`) into [StockLocationAvailability].
/// - Map every transport/HTTP failure onto the shared [StockLookupResult]
///   taxonomy via [mapBusinessCentralError] — see [_mapFailure].
/// - Read the bearer token through the existing [AuthSessionStore] seam, and
///   hand off to [SessionExpiryCoordinator] exactly like
///   `InventoryService`/`ItemsService` on a missing session or a confirmed
///   HTTP 401 — returning [StockLookupSessionExpired] rather than throwing,
///   since [StockLookupService.lookup] never throws for an expected failure.
///
/// Must not:
/// - Send any request parameter besides `page`/`per_page`/`item_no`, fall
///   back to downloading/filtering the unfiltered catalog, or resolve
///   through `/items`/`commonItemNo`.
/// - Talk to Business Central directly — only [AncApiClient], which talks
///   only to the ANC API.
class ApiStockLookupService implements StockLookupService {
  ApiStockLookupService({
    AncApiClient? apiClient,
    AuthSessionStore? sessionStore,
    SessionExpiryCoordinator? coordinator,
  }) : _apiClient = apiClient ?? AncApiClient(),
       _ownsApiClient = apiClient == null,
       _sessionStore = sessionStore ?? SecureAuthSessionStore(),
       _coordinator = coordinator ?? sessionExpiryCoordinator;

  final AncApiClient _apiClient;
  final bool _ownsApiClient;
  final AuthSessionStore _sessionStore;
  final SessionExpiryCoordinator _coordinator;

  /// Fixed `per_page` for every filtered inventory request this service
  /// sends, per the confirmed production contract.
  static const int _perPage = 100;

  /// Hard cap on filtered pages fetched for one lookup — defensive only.
  /// One item's open inventory rows are never expected to approach
  /// [_maxPages] * [_perPage] rows; this exists solely to guarantee this
  /// method terminates even if the backend's pagination metadata is
  /// malformed or a bug always returns a full page.
  static const int _maxPages = 50;

  @override
  Future<StockLookupResult> lookup(String rawCode) async {
    final itemNo = rawCode.trim();
    if (itemNo.isEmpty) return StockLookupInvalidCode(rawCode);

    final session = await _sessionStore.read();
    if (session == null) {
      // Defensive: an authenticated caller should never reach this screen
      // without a stored session, but if it happens there is nothing to
      // gain by pretending otherwise — route through the same centralized
      // path a confirmed 401 would.
      await _coordinator.handleUnauthorized();
      return StockLookupSessionExpired(rawCode);
    }

    final _PageFetch fetch;
    try {
      fetch = await _fetchAllFilteredPages(
        token: session.token,
        itemNo: itemNo,
      );
    } on AncApiException catch (error) {
      return _mapFailure(rawCode, error);
    }

    if (!fetch.complete) {
      // Malformed pagination metadata or the defensive page cap was hit —
      // never build a StockLookupSuccess from a partial/truncated row set.
      return StockLookupUnexpectedFailure(rawCode);
    }
    final rows = fetch.rows;

    // Defensive: only trust rows that actually match the requested item —
    // the request is already filtered server-side, but a lookup must never
    // accidentally surface another item's stock — and only open rows count
    // as available.
    final openMatches = rows
        .where((row) => row.itemNo == itemNo && row.open)
        .toList(growable: false);

    if (openMatches.isEmpty) {
      // No open inventory anywhere — before reporting a bare "not found",
      // check whether more stock is already on a purchase order (see
      // _expectedRestockDate); the UI shows that date beside the
      // out-of-stock status.
      return StockLookupNotFound(
        rawCode,
        expectedRestockDate: await _expectedRestockDate(
          token: session.token,
          itemNo: itemNo,
        ),
      );
    }

    final availability = _aggregateByLocation(openMatches);
    final result = StockLookupSuccess(
      rawCode,
      scannedAt: DateTime.now(),
      itemNo: itemNo,
      description: _firstDescription(openMatches),
      availabilityByLocation: availability,
    );

    // Only an out-of-stock result (summed quantity <= 0 — the red status)
    // warrants the extra purchase-orders round-trip; in-stock/low results
    // never show a restock date.
    if (result.combinedAvailabilityLevel != StockAvailabilityLevel.outOfStock) {
      return result;
    }

    return StockLookupSuccess(
      rawCode,
      scannedAt: result.scannedAt,
      itemNo: itemNo,
      description: result.description,
      availabilityByLocation: availability,
      expectedRestockDate: await _expectedRestockDate(
        token: session.token,
        itemNo: itemNo,
      ),
    );
  }

  /// Hard cap on filtered purchase-order pages fetched per lookup — same
  /// defensive-only reasoning as [_maxPages], sized smaller because one
  /// item's open purchase-order lines are a far smaller set than its
  /// inventory ledger.
  static const int _maxPurchaseOrderPages = 10;

  /// The earliest purchase-order `Expected_Receipt_Date` strictly after
  /// [searchedAt] (defaulting to now — "the date searched") for the exact
  /// [itemNo] variation, via `GET
  /// /api/business-central/purchase-orders?item_no=...`, or `null` when no
  /// such line exists.
  ///
  /// Strictly best-effort: the main stock answer is already known when this
  /// runs, so ANY failure here (transport, HTTP, malformed pagination)
  /// returns `null` rather than degrading a valid out-of-stock result into
  /// an error state. Rows are re-checked against [itemNo] client-side —
  /// same defensive exact-match rule as the inventory fetch — so another
  /// variation's incoming stock is never shown for this one.
  Future<DateTime?> _expectedRestockDate({
    required String token,
    required String itemNo,
    DateTime? searchedAt,
  }) async {
    // Date-only comparison ("after the date searched"): receipt dates are
    // date-only values, so the threshold is normalized to midnight —
    // tomorrow's expected receipt counts, today's does not.
    final searched = searchedAt ?? DateTime.now();
    final threshold = DateTime(searched.year, searched.month, searched.day);
    DateTime? earliest;

    try {
      var requestedPage = 1;
      var previousCurrentPage = 0;

      for (var i = 0; i < _maxPurchaseOrderPages; i++) {
        final response = await _apiClient.fetchPurchaseOrders(
          token: token,
          itemNo: itemNo,
          page: requestedPage,
          perPage: _perPage,
        );

        final currentPage = response.currentPage;
        final lastPage = response.lastPage;
        final malformed =
            currentPage < 1 ||
            lastPage < 1 ||
            currentPage > lastPage ||
            currentPage != requestedPage ||
            currentPage <= previousCurrentPage;
        if (malformed) return earliest;

        for (final PurchaseOrderLine line in response.data) {
          final date = line.expectedReceiptDate;
          if (line.itemNo != itemNo || date == null) continue;
          if (!date.isAfter(threshold)) continue;
          if (earliest == null || date.isBefore(earliest)) earliest = date;
        }

        if (response.isLastPage) return earliest;
        previousCurrentPage = currentPage;
        requestedPage = currentPage + 1;
      }
    } catch (_) {
      // Deliberately broader than the usual `on AncApiException`: this
      // enrichment runs after the primary stock answer is already known,
      // and no failure in it — expected or not — may replace a valid
      // out-of-stock result with an error.
      return earliest;
    }

    return earliest;
  }

  /// Fetches every filtered (`item_no`-scoped) page for [itemNo], starting
  /// at page 1 and following the backend's `current_page`/`last_page`
  /// fields (never `next_page_url`) to decide whether another page exists —
  /// see the class-level doc comment.
  ///
  /// Returns [_PageFetch.complete] `false` — with whatever partial [rows]
  /// had been collected so far discarded by the caller — the instant any
  /// response's metadata cannot be trusted:
  /// - `current_page` is `< 1`, or `> last_page`;
  /// - `current_page` does not equal the page number just requested (a
  ///   backend/desync bug);
  /// - `current_page` does not strictly increase from the previous
  ///   response's (never advancing, repeating, or regressing — the
  ///   textbook infinite-loop shape);
  /// - [_maxPages] requests have been made without ever reaching the last
  ///   page (defensive bound against, e.g., a `last_page` that is itself
  ///   corrupted/absurd).
  Future<_PageFetch> _fetchAllFilteredPages({
    required String token,
    required String itemNo,
  }) async {
    final rows = <BusinessCentralInventoryEntry>[];
    var requestedPage = 1;
    var previousCurrentPage = 0;

    for (var iteration = 0; iteration < _maxPages; iteration++) {
      final response = await _apiClient.fetchInventory(
        token: token,
        page: requestedPage,
        perPage: _perPage,
        itemNo: itemNo,
      );

      final currentPage = response.currentPage;
      final lastPage = response.lastPage;
      final malformed =
          currentPage < 1 ||
          lastPage < 1 ||
          currentPage > lastPage ||
          currentPage != requestedPage ||
          currentPage <= previousCurrentPage;
      if (malformed) return const _PageFetch.incomplete();

      rows.addAll(response.data);
      if (response.isLastPage) return _PageFetch.complete(rows);

      previousCurrentPage = currentPage;
      requestedPage = currentPage + 1;
    }

    // Exceeded the defensive page cap without ever reaching the last page.
    return const _PageFetch.incomplete();
  }

  /// The first non-empty description among [rows], in the order returned by
  /// the backend — deterministic, and `null` (never a fabricated value) when
  /// every row's description is empty.
  static String? _firstDescription(List<BusinessCentralInventoryEntry> rows) {
    for (final row in rows) {
      if (row.description.isNotEmpty) return row.description;
    }
    return null;
  }

  /// Sums `remainingQuantity` across [rows] grouped by
  /// (`locationCode`, `unitOfMeasureCode`), preserving each group's
  /// first-seen order.
  static List<StockLocationAvailability> _aggregateByLocation(
    List<BusinessCentralInventoryEntry> rows,
  ) {
    final totals = <(String, String), num>{};
    final order = <(String, String)>[];
    for (final row in rows) {
      final key = (row.locationCode, row.unitOfMeasureCode);
      if (!totals.containsKey(key)) order.add(key);
      totals[key] = (totals[key] ?? 0) + row.remainingQuantity;
    }
    return [
      for (final key in order)
        StockLocationAvailability(
          locationCode: key.$1,
          remainingQuantity: totals[key]!,
          unitOfMeasureCode: key.$2,
        ),
    ];
  }

  Future<StockLookupResult> _mapFailure(
    String rawCode,
    AncApiException error,
  ) async {
    final outcome = mapBusinessCentralError(
      error,
      supportsAccountLinking: false,
    );
    return switch (outcome) {
      BusinessCentralUnauthorized() => await _sessionExpired(rawCode),
      BusinessCentralTemporarilyUnavailable() =>
        StockLookupTemporarilyUnavailable(rawCode),
      BusinessCentralUpstreamFailure() => StockLookupRetryableFailure(rawCode),
      BusinessCentralNetworkFailure() => StockLookupRetryableFailure(rawCode),
      // A 422 (invalid page/per_page, or any other undocumented validation
      // failure) is a request defect, not evidence the scanned code itself
      // is invalid — it must never map to StockLookupInvalidCode.
      BusinessCentralRequestDefect() => StockLookupUnexpectedFailure(rawCode),
      BusinessCentralAccountNotLinked() => StockLookupUnexpectedFailure(
        rawCode,
      ),
      BusinessCentralProtocolFailure() => StockLookupUnexpectedFailure(rawCode),
    };
  }

  Future<StockLookupResult> _sessionExpired(String rawCode) async {
    await _coordinator.handleUnauthorized();
    return StockLookupSessionExpired(rawCode);
  }

  /// Closes the underlying [AncApiClient], but only when this instance
  /// created it; a caller-supplied client is left open for the caller to
  /// manage.
  void close() {
    if (_ownsApiClient) _apiClient.close();
  }
}

/// Result of [ApiStockLookupService._fetchAllFilteredPages]: either every
/// filtered page was fetched and validated ([complete] `true`, [rows]
/// populated), or the fetch was abandoned because the backend's pagination
/// metadata could not be trusted or the defensive page cap was hit
/// ([complete] `false`, [rows] always empty — a caller must never treat
/// [rows] as a usable partial result).
class _PageFetch {
  const _PageFetch.complete(this.rows) : complete = true;

  const _PageFetch.incomplete() : complete = false, rows = const [];

  final bool complete;
  final List<BusinessCentralInventoryEntry> rows;
}
