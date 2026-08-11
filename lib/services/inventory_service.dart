import '../config/api_config.dart';
import '../models/business_central/business_central_inventory_entry.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Owns paging through the Business Central inventory endpoint,
/// filtered to one exact `itemNo`, for one caller's lifetime, following the
/// same lifecycle/error-handling architecture as
/// `ItemsService`/`PaymentsService`/`InvoicesService`. Not yet wired to any
/// screen — this is the reusable data-load engine only; `ApiStockLookupService`
/// is the production `itemNo` → availability path.
///
/// CONFIRMED(inventory contract): `GET /api/business-central/inventory`
/// requires `item_no` — a missing value is rejected with HTTP 422. This
/// service therefore requires an exact `itemNo` up front (see
/// [loadFirstPage]) and never pages through the endpoint unfiltered. It
/// still performs no further business filtering — `open`, zero/negative
/// quantities, or location — on the rows the backend returns; see
/// `ApiStockLookupService` for that aggregation.
///
/// Responsibilities:
/// - Load the first page (for the [loadFirstPage]-supplied `itemNo`), load
///   the next page, and refresh (restart from page 1 for the same
///   `itemNo`), always at a fixed page size recorded from the first load.
/// - Advance pagination only by requesting `page: currentPage + 1` against
///   the fixed inventory endpoint with the original `perPage` — never by
///   following a backend-provided `next_page_url`/`first_page_url`/
///   `last_page_url`/`prev_page_url`/`path`, for the same reason as
///   `ItemsService`: a live response for this endpoint is not yet available,
///   and every other Business Central list endpoint's confirmed live
///   pagination URLs have been unsafe/incomplete (observed as a bare
///   `/?page=2` / `/`). Stops once `currentPage >= lastPage`, per the
///   backend's reported page numbers.
/// - Prevent two concurrent requests of the same kind (first-page vs.
///   load-more) from running at once.
/// - Guard against a stale in-flight response (e.g. a slow load-more that
///   resolves after a refresh already replaced page 1) corrupting the
///   current rows, via a monotonic generation counter.
/// - Deduplicate rows by [BusinessCentralInventoryEntry.id] — the
///   documented pagination deduplication identity — when appending a page,
///   preserving the backend's row order.
/// - Preserve already-loaded rows when a load-more (or a refresh) fails.
/// - Read the bearer token through the existing [AuthSessionStore] seam —
///   never a second copy of it.
/// - On HTTP 401, hand off to [SessionExpiryCoordinator] exactly once and
///   throw [SessionExpiredException]; every other failure throws
///   [BusinessCentralFailureException] with already-loaded rows untouched.
///   422 is mapped with `supportsAccountLinking: false` — this data is
///   company-scoped, not tied to a linked Business Central customer, so a
///   422 here must never be presented as "account not linked".
///
/// Must not:
/// - Perform Flutter navigation or show UI itself.
/// - Filter rows by `open`, zero/negative quantities, location, or item
///   number, or aggregate rows by `itemNo`/`locationCode` — those are future
///   business/UI decisions; this service carries raw API rows intact.
class InventoryService {
  InventoryService({
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

  List<BusinessCentralInventoryEntry> _entries = const [];
  int _currentPage = 1;
  int _lastPage = 1;

  /// The exact Business Central `itemNo` this session is scoped to — set by
  /// [loadFirstPage] and reused by every subsequent [loadNextPage]/[refresh]
  /// call. `null` until [loadFirstPage] has been called at least once.
  String? _itemNo;

  /// The fixed `per_page` size sent on every request — page 1 and every
  /// subsequent `loadNextPage()` call alike — so the effective page size
  /// never drifts across a paging session.
  final int _perPage = ApiConfig.businessCentralDefaultPerPage;

  bool _isLoadingFirstPage = false;
  bool _isLoadingMore = false;

  /// Bumped at the start of every first-page load (initial load or
  /// refresh), so a load-more response that resolves after a newer refresh
  /// has already started can recognize itself as stale and discard its
  /// result instead of corrupting the freshly-refreshed rows.
  int _generation = 0;

  /// Rows loaded so far, oldest page first. Never mutated in place —
  /// always replaced wholesale so callers holding a previous reference
  /// never see a partially-updated list.
  List<BusinessCentralInventoryEntry> get entries => _entries;

  /// Whether a subsequent page exists, per the backend's reported
  /// `current_page`/`last_page` numbers — never a `next_page_url`. See the
  /// class-level doc comment for why.
  bool get hasNextPage => _currentPage < _lastPage;

  /// The most recently loaded page number, per the backend's response.
  int get currentPage => _currentPage;

  /// The last page number for the current query, per the backend's
  /// response.
  int get lastPage => _lastPage;

  bool get isLoadingFirstPage => _isLoadingFirstPage;
  bool get isLoadingMore => _isLoadingMore;

  /// Loads page 1, filtered to the exact Business Central [itemNo] — see the
  /// class-level doc comment on why this is now required (a missing
  /// `item_no` is rejected by the backend with HTTP 422). Safe to call while
  /// already loading (a duplicate call is ignored) — see [refresh] for
  /// restarting an already-loaded list for the same [itemNo].
  ///
  /// Throws [ArgumentError] if [itemNo] is blank (empty or whitespace-only)
  /// rather than silently sending — or omitting — an empty `item_no`; this
  /// service must never generate an unfiltered inventory request.
  Future<void> loadFirstPage({required String itemNo}) {
    if (itemNo.trim().isEmpty) {
      throw ArgumentError.value(itemNo, 'itemNo', 'must not be blank');
    }
    _itemNo = itemNo;
    return _loadFirstPage();
  }

  /// Restarts paging from page 1 for the same `itemNo` last passed to
  /// [loadFirstPage], replacing [entries] only once the new first page
  /// succeeds. Any load-more in flight when this is called will, on
  /// completion, recognize itself as stale (via the generation counter) and
  /// be discarded rather than appended onto the refreshed rows.
  ///
  /// A no-op if [loadFirstPage] has never been called.
  Future<void> refresh() {
    if (_itemNo == null) return Future<void>.value();
    return _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final itemNo = _itemNo;
    if (itemNo == null) return; // loadFirstPage(itemNo:) never called
    if (_isLoadingFirstPage) return;
    _isLoadingFirstPage = true;
    final myGeneration = ++_generation;

    try {
      final token = await _requireToken();
      final page = await _apiClient.fetchInventory(
        token: token,
        itemNo: itemNo,
        page: 1,
        perPage: _perPage,
      );
      if (myGeneration != _generation) return; // superseded by a newer call

      _entries = _deduplicated(page.data, against: const []);
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return; // stale failure, ignore
      await _handleFailure(error);
    } finally {
      _isLoadingFirstPage = false;
    }
  }

  /// Loads the next page (per [hasNextPage]) and appends it to [entries],
  /// requesting `page: currentPage + 1` at the recorded [_perPage] — never
  /// a backend-provided URL. Ignored while a first-page load or another
  /// load-more is already in flight, and when no next page exists. On
  /// failure, [entries] is left exactly as it was.
  Future<void> loadNextPage() async {
    final itemNo = _itemNo;
    if (itemNo == null) return; // loadFirstPage(itemNo:) never called
    if (_isLoadingFirstPage || _isLoadingMore) return;
    if (!hasNextPage) return;

    _isLoadingMore = true;
    final myGeneration = _generation;
    final requestedPage = _currentPage + 1;

    try {
      final token = await _requireToken();
      final page = await _apiClient.fetchInventory(
        token: token,
        itemNo: itemNo,
        page: requestedPage,
        perPage: _perPage,
      );
      if (myGeneration != _generation) return; // a refresh started meanwhile

      _entries = [..._entries, ..._deduplicated(page.data, against: _entries)];
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return;
      await _handleFailure(error); // _entries is untouched above on failure
    } finally {
      _isLoadingMore = false;
    }
  }

  List<BusinessCentralInventoryEntry> _deduplicated(
    List<BusinessCentralInventoryEntry> incoming, {
    required List<BusinessCentralInventoryEntry> against,
  }) {
    final seen = {for (final entry in against) entry.id};
    final result = <BusinessCentralInventoryEntry>[];
    for (final entry in incoming) {
      if (seen.add(entry.id)) result.add(entry);
    }
    return result;
  }

  Future<String> _requireToken() async {
    final session = await _sessionStore.read();
    if (session == null) {
      // Defensive: an authenticated caller should never be reachable
      // without a stored session, but if this is ever hit there is nothing
      // to gain by pretending otherwise — route through the same
      // centralized path a confirmed 401 would.
      await _coordinator.handleUnauthorized();
      throw const SessionExpiredException();
    }
    return session.token;
  }

  Future<void> _handleFailure(AncApiException error) async {
    final outcome = mapBusinessCentralError(
      error,
      supportsAccountLinking: false,
    );
    if (outcome is BusinessCentralUnauthorized) {
      await _coordinator.handleUnauthorized();
      throw const SessionExpiredException();
    }
    throw BusinessCentralFailureException(outcome);
  }

  /// Closes the underlying [AncApiClient], but only when this instance
  /// created it; a caller-supplied client is left open for the caller to
  /// manage.
  void close() {
    if (_ownsApiClient) _apiClient.close();
  }
}
