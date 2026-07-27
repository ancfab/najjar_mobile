import '../models/business_central/ledger_entry.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Owns paging through the Business Central ledger-entries
/// endpoint for one screen's lifetime — the first reusable "load a Business
/// Central list" engine, meant to be followed by the same shape for
/// payments/invoices/credit memos later.
///
/// Responsibilities:
/// - Load the first page, load the next page, and refresh (restart from
///   page 1), always at a fixed page size of 25.
/// - Prevent two concurrent requests of the same kind (first-page vs.
///   load-more) from running at once.
/// - Guard against a stale in-flight response (e.g. a slow load-more that
///   resolves after a refresh already replaced page 1) corrupting the
///   current rows, via a monotonic generation counter.
/// - Deduplicate rows by `Entry_No` when appending a page.
/// - Preserve already-loaded rows when a load-more (or a refresh) fails.
/// - Read the bearer token through the existing [AuthSessionStore] seam —
///   never a second copy of it.
/// - On HTTP 401, hand off to [SessionExpiryCoordinator] exactly once and
///   throw [SessionExpiredException]; every other failure throws
///   [BusinessCentralFailureException] with already-loaded rows untouched.
///
/// Must not:
/// - Perform Flutter navigation or show UI itself.
/// - Send a customer identifier as a query parameter.
class LedgerEntriesService {
  LedgerEntriesService({
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

  List<LedgerEntry> _entries = const [];
  int _currentPage = 1;
  int _lastPage = 1;
  String? _nextPageUrl;

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
  List<LedgerEntry> get entries => _entries;

  /// Whether a subsequent page exists, per the backend's `next_page_url` —
  /// the source of truth for whether to keep paging (see
  /// `PaginatedResponse.hasNextPage`).
  bool get hasNextPage => _nextPageUrl != null;

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

  /// Restarts paging from page 1, replacing [entries] only once the new
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
      final page = await _apiClient.fetchLedgerEntries(
        token: token,
        page: 1,
        perPage: 25,
      );
      if (myGeneration != _generation) return; // superseded by a newer call

      _entries = _deduplicated(page.data, against: const []);
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
      _nextPageUrl = page.nextPageUrl;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return; // stale failure, ignore
      await _handleFailure(error);
    } finally {
      _isLoadingFirstPage = false;
    }
  }

  /// Loads the next page (per [hasNextPage]) and appends it to [entries].
  /// Ignored while a first-page load or another load-more is already in
  /// flight, and when no next page exists. On failure, [entries] is left
  /// exactly as it was.
  Future<void> loadNextPage() async {
    if (_isLoadingFirstPage || _isLoadingMore) return;
    final url = _nextPageUrl;
    if (url == null) return;

    _isLoadingMore = true;
    final myGeneration = _generation;

    try {
      final token = await _requireToken();
      final page = await _apiClient.fetchLedgerEntriesPage(
        token: token,
        nextPageUrl: Uri.parse(url),
      );
      if (myGeneration != _generation) return; // a refresh started meanwhile

      _entries = [..._entries, ..._deduplicated(page.data, against: _entries)];
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
      _nextPageUrl = page.nextPageUrl;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return;
      await _handleFailure(error); // _entries is untouched above on failure
    } finally {
      _isLoadingMore = false;
    }
  }

  List<LedgerEntry> _deduplicated(
    List<LedgerEntry> incoming, {
    required List<LedgerEntry> against,
  }) {
    final seen = {for (final entry in against) entry.entryNo};
    final result = <LedgerEntry>[];
    for (final entry in incoming) {
      if (seen.add(entry.entryNo)) result.add(entry);
    }
    return result;
  }

  Future<String> _requireToken() async {
    final session = await _sessionStore.read();
    if (session == null) {
      // Defensive: an authenticated screen should never be reachable
      // without a stored session, but if this is ever hit there is nothing
      // to gain by pretending otherwise — route through the same
      // centralized path a confirmed 401 would.
      await _coordinator.handleUnauthorized();
      throw const SessionExpiredException();
    }
    return session.token;
  }

  Future<void> _handleFailure(AncApiException error) async {
    final outcome = mapBusinessCentralError(error);
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
