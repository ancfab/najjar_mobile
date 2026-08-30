import '../models/business_central/customer_details.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Loads a single Business Central customer-details snapshot, for
/// the Account Balance screen's hero balance/Credit Utilization figures and
/// its Balance by Period section.
///
/// Follows the same token/error-handling architecture as
/// `LastPaymentService`/`LedgerEntriesService`:
/// - Reads the bearer token through the existing [AuthSessionStore] seam —
///   never a second copy of it.
/// - On HTTP 401, hands off to [SessionExpiryCoordinator] exactly once and
///   throws [SessionExpiredException].
/// - Every other failure throws [BusinessCentralFailureException].
class CustomerDetailsService {
  CustomerDetailsService({
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

  /// Fetches the authenticated customer's details, optionally scoped to
  /// [dateFrom]/[dateTo] (both optional per the confirmed contract).
  Future<CustomerDetails> fetchCustomerDetails({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final token = await _requireToken();
    try {
      return await _apiClient.fetchCustomerDetails(
        token: token,
        dateFrom: dateFrom,
        dateTo: dateTo,
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
