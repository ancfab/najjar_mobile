import '../config/api_config.dart';
import '../models/business_central/business_central_item.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Owns paging through the Business Central items (product
/// catalog) endpoint for one caller's lifetime, following the same
/// lifecycle/error-handling architecture as `PaymentsService`/
/// `InvoicesService`. Not yet wired to any screen — this is the reusable
/// data-load engine only.
///
/// Responsibilities:
/// - Load the first page, load the next page, and refresh (restart from
///   page 1), always at a fixed page size recorded from the first load.
/// - Advance pagination only by requesting `page: currentPage + 1` against
///   the fixed items endpoint with the original `perPage` — never by
///   following a backend-provided `next_page_url`/`first_page_url`/
///   `last_page_url`/`prev_page_url`/`path`, since those have been
///   confirmed live to drop the endpoint path (`next_page_url: "/?page=2"`,
///   `path: "/"`), the same problem already documented for ledger
///   entries/payments/invoices. Stops once `currentPage >= lastPage`, per
///   the backend's reported page numbers.
/// - Prevent two concurrent requests of the same kind (first-page vs.
///   load-more) from running at once.
/// - Guard against a stale in-flight response (e.g. a slow load-more that
///   resolves after a refresh already replaced page 1) corrupting the
///   current rows, via a monotonic generation counter.
/// - Deduplicate rows by [BusinessCentralItem.id] — a stable UUID-like
///   identity confirmed by the live response — when appending a page,
///   preserving the backend's row order. Never dedupe by `commonItemNo`:
///   multiple item variants share the same `commonItemNo`.
/// - Preserve already-loaded rows when a load-more (or a refresh) fails.
/// - Read the bearer token through the existing [AuthSessionStore] seam —
///   never a second copy of it.
/// - On HTTP 401, hand off to [SessionExpiryCoordinator] exactly once and
///   throw [SessionExpiredException]; every other failure throws
///   [BusinessCentralFailureException] with already-loaded rows untouched.
///   422 is mapped with `supportsAccountLinking: false` — this catalog is
///   company-scoped, not tied to a linked Business Central customer, so a
///   422 here must never be presented as "account not linked".
///
/// Must not:
/// - Perform Flutter navigation or show UI itself.
/// - Filter out blocked items — [BusinessCentralItem.blocked] is carried
///   through untouched for a later UI/business decision.
class ItemsService {
  ItemsService({
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

  List<BusinessCentralItem> _items = const [];
  int _currentPage = 1;
  int _lastPage = 1;

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
  List<BusinessCentralItem> get items => _items;

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

  /// Loads page 1. Safe to call while already loading (a duplicate call is
  /// ignored) — see [refresh] for restarting an already-loaded list.
  Future<void> loadFirstPage() => _loadFirstPage();

  /// Restarts paging from page 1, replacing [items] only once the new
  /// first page succeeds. Any load-more in flight when this is called will,
  /// on completion, recognize itself as stale (via the generation counter)
  /// and be discarded rather than appended onto the refreshed rows.
  Future<void> refresh() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    if (_isLoadingFirstPage) return;
    _isLoadingFirstPage = true;
    final myGeneration = ++_generation;

    try {
      final token = await _requireToken();
      final page = await _apiClient.fetchItems(
        token: token,
        page: 1,
        perPage: _perPage,
      );
      if (myGeneration != _generation) return; // superseded by a newer call

      _items = _deduplicated(page.data, against: const []);
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return; // stale failure, ignore
      await _handleFailure(error);
    } finally {
      _isLoadingFirstPage = false;
    }
  }

  /// Loads the next page (per [hasNextPage]) and appends it to [items],
  /// requesting `page: currentPage + 1` at the recorded [_perPage] — never
  /// a backend-provided URL. Ignored while a first-page load or another
  /// load-more is already in flight, and when no next page exists. On
  /// failure, [items] is left exactly as it was.
  Future<void> loadNextPage() async {
    if (_isLoadingFirstPage || _isLoadingMore) return;
    if (!hasNextPage) return;

    _isLoadingMore = true;
    final myGeneration = _generation;
    final requestedPage = _currentPage + 1;

    try {
      final token = await _requireToken();
      final page = await _apiClient.fetchItems(
        token: token,
        page: requestedPage,
        perPage: _perPage,
      );
      if (myGeneration != _generation) return; // a refresh started meanwhile

      _items = [..._items, ..._deduplicated(page.data, against: _items)];
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return;
      await _handleFailure(error); // _items is untouched above on failure
    } finally {
      _isLoadingMore = false;
    }
  }

  List<BusinessCentralItem> _deduplicated(
    List<BusinessCentralItem> incoming, {
    required List<BusinessCentralItem> against,
  }) {
    final seen = {for (final item in against) item.id};
    final result = <BusinessCentralItem>[];
    for (final item in incoming) {
      if (seen.add(item.id)) result.add(item);
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
