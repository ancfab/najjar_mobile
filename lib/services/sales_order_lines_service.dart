import '../config/api_config.dart';
import '../models/business_central/paginated_response.dart';
import '../models/business_central/sales_order_line.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Loads exactly one page of the authenticated customer's Business
/// Central sales-order lines, for the Orders screen's explicit
/// Previous/Next pagination.
///
/// Unlike `LedgerEntriesService`/`InvoicesService` (which accumulate every
/// page loaded so far into one long list), this class fetches and returns a
/// single page at a time — the Orders screen shows one page's rows, not an
/// ever-growing list, so there is nothing to accumulate or deduplicate
/// across pages here.
///
/// Follows the same token/error-handling architecture as `LastPaymentService`/
/// `CurrentBalanceService`:
/// - Reads the bearer token through the existing [AuthSessionStore] seam —
///   never a second copy of it.
/// - Requests `page`/`per_page` against the fixed sales-orders endpoint —
///   never a backend-provided `next_page_url`/`prev_page_url`, so a
///   compromised/malformed response body can never redirect a request to an
///   untrusted host.
/// - On HTTP 401, hands off to [SessionExpiryCoordinator] exactly once and
///   throws [SessionExpiredException]. Every other failure throws
///   [BusinessCentralFailureException].
class SalesOrderLinesService {
  SalesOrderLinesService({
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

  /// Fetches [page] (1-indexed) at [perPage] rows per page — never a page
  /// less than 1, never a `perPage` outside
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// (both clamped by [AncApiClient.fetchSalesOrders] itself).
  Future<PaginatedResponse<BusinessCentralSalesOrderLine>> fetchPage({
    required int page,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async {
    final token = await _requireToken();
    try {
      return await _apiClient.fetchSalesOrders(
        token: token,
        page: page,
        perPage: perPage,
      );
    } on AncApiException catch (error) {
      final outcome = mapBusinessCentralError(error);
      if (outcome is BusinessCentralUnauthorized) {
        await _coordinator.handleUnauthorized();
        throw const SessionExpiredException();
      }
      throw BusinessCentralFailureException(outcome);
    }
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

  /// Closes the underlying [AncApiClient], but only when this instance
  /// created it; a caller-supplied client is left open for the caller to
  /// manage.
  void close() {
    if (_ownsApiClient) _apiClient.close();
  }
}
