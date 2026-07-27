import '../config/api_config.dart';
import '../models/business_central/business_central_invoice_line.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Owns paging through the Business Central invoices endpoint for
/// one caller's lifetime, following the same lifecycle/error-handling
/// architecture as `PaymentsService`. Not yet wired to any screen — this is
/// the reusable data-load engine only.
///
/// Responsibilities:
/// - Load the first page, load the next page, and refresh (restart from
///   page 1), always at a fixed page size recorded from the first load.
/// - Advance pagination only by requesting `page: currentPage + 1` against
///   the fixed invoices endpoint with the original `perPage` — never by
///   following a backend-provided `next_page_url`/`first_page_url`/
///   `last_page_url`/`prev_page_url`/`path`. The confirmed live envelope has
///   returned unsafe/incomplete values for these (e.g. `next_page_url:
///   "/?page=2"`, `path: "/"`), the same problem already documented for
///   Ledger entries. Stops once `currentPage >= lastPage`, per the
///   backend's reported page numbers.
/// - Prevent two concurrent requests of the same kind (first-page vs.
///   load-more) from running at once.
/// - Guard against a stale in-flight response (e.g. a slow load-more that
///   resolves after a refresh already replaced page 1) corrupting the
///   current rows, via a monotonic generation counter.
/// - Deduplicate rows by the composite `Document_No` + `Line_No` identity
///   when appending a page, preserving the backend's row order.
///   `Document_No` alone is not a unique row identity: the confirmed live
///   response has shown the same `Document_No` spanning a page boundary
///   (e.g. page 1 ending with `Line_No 20000`, page 2 beginning with the
///   same `Document_No` at `Line_No 30000`) — both rows are distinct lines
///   of the same invoice and must both be kept.
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
/// - Sort rows, group rows by `Document_No` into a complete invoice, or
///   compute a subtotal/VAT/total — this class is transport/pagination
///   only, over flat invoice lines. Grouping and totals are a separate,
///   not-yet-built phase.
class InvoicesService {
  InvoicesService({
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

  List<BusinessCentralInvoiceLine> _lines = const [];
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

  /// Flat invoice-line rows loaded so far, oldest page first, in exact
  /// backend order — never sorted or grouped by `Document_No`. Never
  /// mutated in place — always replaced wholesale so callers holding a
  /// previous reference never see a partially-updated list.
  List<BusinessCentralInvoiceLine> get lines => _lines;

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

  /// Restarts paging from page 1, replacing [lines] only once the new first
  /// page succeeds. Any load-more in flight when this is called will, on
  /// completion, recognize itself as stale (via the generation counter) and
  /// be discarded rather than appended onto the refreshed rows.
  Future<void> refresh() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    if (_isLoadingFirstPage) return;
    _isLoadingFirstPage = true;
    final myGeneration = ++_generation;

    try {
      final token = await _requireToken();
      final page = await _apiClient.fetchInvoices(
        token: token,
        page: 1,
        perPage: _perPage,
      );
      if (myGeneration != _generation) return; // superseded by a newer call

      _lines = _deduplicated(page.data, against: const []);
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return; // stale failure, ignore
      await _handleFailure(error);
    } finally {
      _isLoadingFirstPage = false;
    }
  }

  /// Loads the next page (per [hasNextPage]) and appends it to [lines],
  /// requesting `page: currentPage + 1` at the recorded [_perPage] — never
  /// a backend-provided URL. Ignored while a first-page load or another
  /// load-more is already in flight, and when no next page exists. On
  /// failure, [lines] is left exactly as it was.
  Future<void> loadNextPage() async {
    if (_isLoadingFirstPage || _isLoadingMore) return;
    if (!hasNextPage) return;

    _isLoadingMore = true;
    final myGeneration = _generation;
    final requestedPage = _currentPage + 1;

    try {
      final token = await _requireToken();
      final page = await _apiClient.fetchInvoices(
        token: token,
        page: requestedPage,
        perPage: _perPage,
      );
      if (myGeneration != _generation) return; // a refresh started meanwhile

      _lines = [..._lines, ..._deduplicated(page.data, against: _lines)];
      _currentPage = page.currentPage;
      _lastPage = page.lastPage;
    } on AncApiException catch (error) {
      if (myGeneration != _generation) return;
      await _handleFailure(error); // _lines is untouched above on failure
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Composite `Document_No` + `Line_No` identity string — `Document_No`
  /// alone is not a unique row identity (see the class-level doc comment),
  /// so this must never be simplified to `documentNo` on its own.
  String _identityOf(BusinessCentralInvoiceLine line) =>
      '${line.documentNo}\u0000${line.lineNo}';

  List<BusinessCentralInvoiceLine> _deduplicated(
    List<BusinessCentralInvoiceLine> incoming, {
    required List<BusinessCentralInvoiceLine> against,
  }) {
    final seen = {for (final line in against) _identityOf(line)};
    final result = <BusinessCentralInvoiceLine>[];
    for (final line in incoming) {
      if (seen.add(_identityOf(line))) result.add(line);
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
