import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/business_central/zebra_sales_order_line.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'business_central_error_mapper.dart' show SessionExpiredException;
import 'secure_auth_session_store.dart';
import 'session_expiry_coordinator.dart';

/// Purpose: Fetches every Zebra sales-order line for one order, as a
/// best-effort ENRICHMENT of the Order Detail screen — never a required
/// data source.
///
/// [documentNo] here is whatever identifier `OrderDetailScreen` already has
/// for the order it just loaded via `OrderDetailService`: usually the plain
/// Sales Order page's own order GUID (that page has no human document
/// number field at all on most tenants), but it may also be a real Zebra
/// `documentNo` (e.g. "ZR-45149") if the screen already resolved one from
/// an earlier Zebra fetch. This class does not need to know or care which
/// kind it has - the ANC API resolves either one server-side (see
/// `AncApiClient.fetchZebraSalesOrders`'s doc comment) - it only needs to
/// re-check the returned rows actually match ONE of the two identifiers a
/// row could plausibly be asked for by ([BusinessCentralZebraSalesOrderLine.documentNo]
/// or [BusinessCentralZebraSalesOrderLine.orderId]), the same "never trust
/// the server-side filter blindly" defensive stance `OrderDetailService`
/// takes for the plain Sales Order endpoint.
///
/// Not every order is a Zebra order, and not every company has this
/// integration published at all - Business Central may 404/503/error, or
/// simply return zero rows, for a perfectly normal order. [fetchOrder]
/// treats every one of those as "no Zebra detail for this order" (an empty
/// list), NEVER as a failure to surface on the Order Detail screen - the
/// screen's primary content (from `OrderDetailService`) already loaded
/// successfully by the time this runs, and a missing enrichment must never
/// turn that into an error state or a retry prompt. The one exception is
/// HTTP 401: a dead session is a real, app-wide concern regardless of which
/// endpoint discovers it, so this still hands off to
/// [SessionExpiryCoordinator] and throws [SessionExpiredException] exactly
/// like every other authenticated call in this app, rather than also
/// swallowing that.
///
/// Mirrors `OrderDetailService`'s pagination (loop `current_page` to
/// `last_page`, largest allowed page size, [_maxPages] safety cap) and
/// deduplication-by-identity, since Zebra orders are expected to be small
/// (a handful of lines) but there is no reason to assume they always fit on
/// one page.
class ZebraOrderDetailService {
  ZebraOrderDetailService({
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

  static const int _perPage = ApiConfig.businessCentralMaxPerPage;

  /// Same hard safety cap as `OrderDetailService._maxPages` - far beyond any
  /// realistic number of lines on one order.
  static const int _maxPages = 200;

  /// Fetches every Zebra sales-order line whose `Document_No` or `orderId`
  /// equals [documentNo]. Returns an empty list whenever there is no Zebra
  /// detail for this order - no such order, this company has no Zebra
  /// integration, or the request failed for any reason other than HTTP 401
  /// (see the class doc comment) - never throws for those cases.
  Future<List<BusinessCentralZebraSalesOrderLine>> fetchOrder({
    required String documentNo,
  }) async {
    debugPrint('[ZEBRA ORDER DETAIL] document_no: $documentNo');

    final String token;
    try {
      final session = await _sessionStore.read();
      if (session == null) {
        // No session to even try with - the primary OrderDetailService call
        // this always follows would already have hit the same wall and
        // handed off to the session coordinator, so there is nothing
        // further to do here beyond declining to make a doomed request.
        return const [];
      }
      token = session.token;
    } catch (error) {
      // A secure-storage read failure (SessionStorageException, or a
      // missing platform channel in a widget-test environment) is exactly
      // the kind of thing this best-effort enrichment must never propagate
      // - OrderDetailService's own read of the SAME store already
      // succeeded for the primary fetch to have gotten this far, so
      // treating a failure here as "no Zebra detail" (never a crash, never
      // a session-expiry side effect of its own) is safe.
      debugPrint('[ZEBRA ORDER DETAIL] treating session read failure ($error) as no Zebra detail.');
      return const [];
    }

    final seenIdentities = <String>{};
    final lines = <BusinessCentralZebraSalesOrderLine>[];
    var page = 1;
    var lastPage = 1;

    try {
      do {
        if (page > _maxPages) return const [];
        final response = await _apiClient.fetchZebraSalesOrders(
          token: token,
          page: page,
          perPage: _perPage,
          documentNo: documentNo,
        );
        debugPrint('[ZEBRA ORDER DETAIL] raw rows: ${response.data.length}');
        lastPage = response.lastPage;
        for (final line in response.data) {
          if (line.documentNo != documentNo && line.orderId != documentNo) {
            continue;
          }
          if (seenIdentities.add(line.identity)) lines.add(line);
        }
        page = response.currentPage + 1;
      } while (page <= lastPage);
    } on AncHttpException catch (error) {
      if (error.statusCode == 401) {
        await _coordinator.handleUnauthorized();
        throw const SessionExpiredException();
      }
      debugPrint('[ZEBRA ORDER DETAIL] treating HTTP ${error.statusCode} as no Zebra detail.');
      return const [];
    } on AncApiException catch (error) {
      debugPrint('[ZEBRA ORDER DETAIL] treating ${error.runtimeType} as no Zebra detail.');
      return const [];
    }

    debugPrint('[ZEBRA ORDER DETAIL] deduplicated rows: ${lines.length}');
    return lines;
  }

  /// Closes the underlying [AncApiClient], but only when this instance
  /// created it; a caller-supplied client is left open for the caller to
  /// manage.
  void close() {
    if (_ownsApiClient) _apiClient.close();
  }
}
