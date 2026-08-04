import '../models/business_central/payment_entry.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Picks the newest [PaymentEntry] in [entries] under the confirmed
/// Payments API contract: rows are returned newest-first by `postingDate`,
/// and when two rows share the same `postingDate` the higher `entryNo` is
/// the newer one. Returns `null` for an empty list.
///
/// Deliberately never just trusts `entries.first` — this stays correct even
/// if the endpoint's `per_page` limit is not honored exactly, or two rows
/// tie on `postingDate`.
PaymentEntry? selectLatestPayment(List<PaymentEntry> entries) {
  if (entries.isEmpty) return null;
  return entries.reduce((newest, candidate) {
    if (candidate.postingDate.isAfter(newest.postingDate)) return candidate;
    if (candidate.postingDate.isBefore(newest.postingDate)) return newest;
    return candidate.entryNo > newest.entryNo ? candidate : newest;
  });
}

/// Purpose: Loads only the single most recent Business Central payment, for
/// the Home screen's Last Payment row.
///
/// Requests `GET /api/business-central/payments?page=1&per_page=1` — the
/// confirmed contract guarantees newest-first ordering by `postingDate`
/// (ties broken by the higher `entryNo`), so a single narrow page is
/// sufficient. Deliberately never pages through the full list the way
/// `PaymentsService` does for a browsable history; this class only answers
/// "what is the latest payment," not "show me all of them."
///
/// Follows the same token/error-handling architecture as `PaymentsService`/
/// `LedgerEntriesService`:
/// - Reads the bearer token through the existing [AuthSessionStore] seam —
///   never a second copy of it.
/// - On HTTP 401, hands off to [SessionExpiryCoordinator] exactly once and
///   throws [SessionExpiredException].
/// - Every other failure throws [BusinessCentralFailureException].
class LastPaymentService {
  LastPaymentService({
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

  /// Fetches the newest payment, or `null` when the authenticated customer
  /// has no payments at all.
  Future<PaymentEntry?> fetchLatestPayment() async {
    final token = await _requireToken();
    try {
      final page = await _apiClient.fetchPayments(
        token: token,
        page: 1,
        perPage: 1,
      );
      return selectLatestPayment(page.data);
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
