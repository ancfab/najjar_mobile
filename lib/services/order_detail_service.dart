import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/business_central/sales_order_line.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart';
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Fetches every sales-order line belonging to one confirmed
/// `Document_No`, for the Order Detail screen.
///
/// Unlike `SalesOrderLinesService` (single page, for the Orders list's
/// explicit Previous/Next paging), this class accumulates *every* page for
/// one document — the confirmed contract requires "fetch every required
/// page for that document number", and Order Detail has no paging UI of its
/// own to hand a partial result to.
///
/// Responsibilities:
/// - Call `GET /api/business-central/sales-orders` with `document_no` set
///   on every page request (never only the first), via
///   [AncApiClient.fetchSalesOrders]'s `documentNo` parameter.
/// - Loop pages until `current_page >= last_page`, per the backend's own
///   reported page numbers — never a `next_page_url`, for the same reason
///   as every other Business Central list endpoint in this app (see
///   `SalesOrderLinesService`).
/// - Stop after [_maxPages] pages even if the backend keeps reporting a
///   higher `last_page` than that, so a backend bug can never spin this
///   loop forever — see [_PaginationLoopExceeded].
/// - Deduplicate rows by the composite `Document_No` + `Line_No` identity
///   (`BusinessCentralSalesOrderLine.identity`).
/// - Defensively drop any row whose `Document_No` does not match the
///   requested value instead of trusting the server-side filter blindly —
///   the confirmed contract says the response is pre-filtered, but a row
///   this fetch didn't ask for must never silently end up attributed to the
///   requested order.
/// - Propagate a failure on *any* page as a total failure — an already-
///   accumulated partial result from earlier successful pages is discarded,
///   never returned, per "do not compute a result from a partially failed
///   pagination sequence".
/// - Read the bearer token through the existing [AuthSessionStore] seam —
///   never a second copy of it.
/// - On HTTP 401, hand off to [SessionExpiryCoordinator] exactly once and
///   throw [SessionExpiredException]; every other failure throws
///   [BusinessCentralFailureException].
///
/// An empty returned list (no error thrown) means "no order found for this
/// `Document_No`" — the confirmed contract's HTTP 200 + empty `data` case —
/// and is the caller's (`OrderDetailScreen`'s) signal to show the Order Not
/// Found state.
class OrderDetailService {
  OrderDetailService({
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

  /// Requested at every page, since one order's lines are expected to fit
  /// in very few pages — using the largest allowed page size minimizes
  /// round trips for this "fetch everything for one document" operation
  /// (unlike the Orders list's fixed 25-per-page UI paging, there is no
  /// user-facing page size to preserve here).
  static const int _perPage = ApiConfig.businessCentralMaxPerPage;

  /// Hard safety cap on pages fetched for a single [fetchOrder] call, far
  /// beyond any realistic number of lines on one sales order — guards
  /// against an infinite loop if a backend defect ever reports a
  /// `last_page` that never converges with `current_page`.
  static const int _maxPages = 200;

  /// Fetches every sales-order line whose `Document_No` equals
  /// [documentNo]. Returns an empty list when the order does not exist
  /// (HTTP 200 + empty `data` on the first page).
  Future<List<BusinessCentralSalesOrderLine>> fetchOrder({
    required String documentNo,
  }) async {
    debugPrint('[ORDER DETAIL] document_no: $documentNo');
    final token = await _requireToken();

    final seenIdentities = <String>{};
    final lines = <BusinessCentralSalesOrderLine>[];
    var page = 1;
    var lastPage = 1;

    try {
      do {
        if (page > _maxPages) {
          throw const BusinessCentralFailureException(
            BusinessCentralProtocolFailure(),
          );
        }
        debugPrint('[ORDER DETAIL] page request: $page');
        final response = await _apiClient.fetchSalesOrders(
          token: token,
          page: page,
          perPage: _perPage,
          documentNo: documentNo,
        );
        debugPrint('[ORDER DETAIL] HTTP status: 200');
        debugPrint('[ORDER DETAIL] raw rows: ${response.data.length}');
        lastPage = response.lastPage;
        for (final line in response.data) {
          if (line.documentNo != documentNo) continue;
          if (seenIdentities.add(line.identity)) lines.add(line);
        }
        page = response.currentPage + 1;
      } while (page <= lastPage);
    } on AncApiException catch (error) {
      if (error is AncHttpException) {
        debugPrint('[ORDER DETAIL] HTTP status: ${error.statusCode}');
      }
      await _handleFailure(error);
    }

    debugPrint('[ORDER DETAIL] deduplicated rows: ${lines.length}');
    return lines;
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
