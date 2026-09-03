import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import '../models/auth/api_validation_error.dart';
import '../models/auth/authenticated_user.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';
import '../models/business_central/business_central_inventory_entry.dart';
import '../models/business_central/business_central_invoice_line.dart';
import '../models/business_central/business_central_item.dart';
import '../models/business_central/business_central_item_search_group.dart';
import '../models/business_central/customer_details.dart';
import '../models/business_central/ledger_entry.dart';
import '../models/business_central/paginated_response.dart';
import '../models/business_central/payment_entry.dart';
import '../models/business_central/purchase_order_line.dart';
import '../models/business_central/sales_order_line.dart';
import 'anc_api_exceptions.dart';

/// Purpose: The single controlled HTTP transport boundary between this app
/// and the ANC API at [ApiConfig.baseUrl].
///
/// Responsibilities:
/// - Build every request URL from [ApiConfig.baseUrl] plus a caller-
///   supplied relative path, rejecting anything that could change the
///   request's scheme, host, or port.
/// - Apply the shared JSON headers every ANC API request needs.
/// - Normalize transport, protocol, and HTTP-level failures into
///   [AncApiException] subtypes — never letting a raw platform exception or
///   a request-construction bug (an [ArgumentError]/[StateError]) be
///   mistaken for a network failure.
///
/// Must not:
/// - Send a request to any host other than [ApiConfig.baseUrl] — in
///   particular, it must never talk to Microsoft Dynamics 365 Business
///   Central directly; the ANC API owns that connection.
/// - Log request bodies, passwords, or tokens.
/// - Attach an Authorization header to the login request.
///
/// [postPublicJson] is deliberately named to make clear it never attaches
/// a Bearer token. [getAuthenticatedJson] is the distinctly-named
/// counterpart for authenticated requests: it requires a token argument
/// rather than adding an optional parameter to the public method that a
/// caller could accidentally omit, and it is the one place that builds the
/// `Authorization: Bearer ...` header — every authenticated ANC API call
/// must go through it rather than constructing that header itself.
class AncApiClient {
  AncApiClient({http.Client? httpClient, Duration? requestTimeout})
    : _httpClient = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null,
      _requestTimeout = requestTimeout ?? ApiConfig.requestTimeout;

  final http.Client _httpClient;

  /// Whether this instance created its own [http.Client] (the production
  /// default) as opposed to receiving a caller-owned one (tests inject
  /// their own fake) — only an owned client is closed by [close].
  final bool _ownsHttpClient;

  /// Per-request timeout. Defaults to [ApiConfig.requestTimeout];
  /// overridable per instance so tests can use a short deterministic value.
  final Duration _requestTimeout;

  static const Map<String, String> _sharedHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  /// Calls `POST /api/auth/login`. Sends only the shared JSON headers — no
  /// Authorization header — since this is the ANC API's one unauthenticated
  /// endpoint used in this phase.
  Future<LoginResponse> login(LoginRequest request) async {
    final response = await postPublicJson(
      ApiConfig.loginPath,
      request.toJson(),
    );
    return _decodeLoginResponse(response);
  }

  /// Calls `GET /api/auth/me` with the given [token] as a Bearer credential,
  /// so a returning user's locally stored token is confirmed against the
  /// backend rather than trusted on its own (see `AuthService.confirmSession`
  /// and `main.dart`'s startup gate). Parses the required top-level `data`
  /// wrapper — never [LoginResponse]'s shape, which this endpoint does not
  /// share.
  Future<AuthenticatedUser> fetchCurrentUser({required String token}) async {
    final response = await getAuthenticatedJson(ApiConfig.mePath, token: token);
    return _decodeCurrentUserResponse(response);
  }

  /// Calls `PATCH /api/auth/me` with the given [token] as a Bearer
  /// credential, updating the authenticated user's `username` and/or
  /// `phone`. At least one of [username]/[phone] must be non-null — the
  /// caller (`AuthService.updateProfile`) enforces this before calling, so
  /// this method sends whichever of the two is supplied, omitting the
  /// other entirely from the body (never as an empty string or `null`
  /// value) rather than deciding a default here.
  ///
  /// Parses the response through the same required top-level `data`
  /// wrapper as [fetchCurrentUser] — per the confirmed contract, this
  /// endpoint returns the updated user in that same shape. Unlike
  /// [fetchCurrentUser], a 422 response's body is parsed into
  /// [ApiValidationError] (see [_decodeUpdateMeResponse]), since the
  /// caller needs field-level `username`/`phone` validation messages.
  Future<AuthenticatedUser> updateMe({
    required String token,
    String? username,
    String? phone,
  }) async {
    final response = await patchAuthenticatedJson(ApiConfig.mePath, {
      'username': ?username,
      'phone': ?phone,
    }, token: token);
    return _decodeUpdateMeResponse(response);
  }

  /// Calls `POST /api/auth/me/avatar` with the given [token] as a Bearer
  /// credential, uploading the file at [filePath] as a multipart/form-data
  /// request under the confirmed field name `avatar`. Per the confirmed
  /// contract, a new upload replaces and deletes the user's previous
  /// avatar server-side — there is no separate remove-avatar endpoint.
  ///
  /// Callers (`AuthService.uploadAvatar`) are responsible for confirming
  /// [filePath] exists and is within the documented 5 MB limit before
  /// calling this method — it does not re-check either, and a file that
  /// disappears between that check and this call surfaces as an
  /// uncontrolled [FileSystemException] from [http.MultipartFile.fromPath],
  /// the same way a malformed [relativePath] surfaces as an uncontrolled
  /// [ArgumentError] elsewhere in this client (see the class doc comment).
  ///
  /// Always sends `image/jpeg` as the part's content type: every avatar
  /// this app uploads has already been through `ImageCropperAvatarCropperService`,
  /// which fixes its output format to JPEG regardless of the original
  /// picked file's format — there is no other source of avatar bytes in
  /// this app to accept a different content type for.
  ///
  /// Reuses [_authenticatedHeaders] (Accept + Authorization only) rather
  /// than [_authenticatedJsonHeaders]: a multipart request's `Content-Type`
  /// (with its boundary parameter) is set by [http.MultipartRequest]
  /// itself, and must never be overridden here.
  ///
  /// Parses the response through the same required top-level `data`
  /// wrapper as [fetchCurrentUser]/[updateMe] — per the confirmed
  /// contract, this endpoint also returns the updated user in that shape,
  /// now including `avatar_url`.
  Future<AuthenticatedUser> uploadAvatar({
    required String token,
    required String filePath,
  }) async {
    debugPrint('[AVATAR DEBUG] AncApiClient.uploadAvatar entered.');
    final uri = _resolve(ApiConfig.meAvatarPath);
    debugPrint('[AVATAR DEBUG] Endpoint: $uri (token never logged).');

    final sourceFile = File(filePath);
    final sourceExists = await sourceFile.exists();
    final sourceLength = sourceExists ? await sourceFile.length() : 0;
    debugPrint('[AVATAR DEBUG] Source file exists: $sourceExists');
    debugPrint('[AVATAR DEBUG] Source file length: $sourceLength bytes');
    debugPrint("[AVATAR DEBUG] Multipart field name: 'avatar'");
    debugPrint(
      '[AVATAR DEBUG] Multipart filename: '
      '${filePath.split(Platform.pathSeparator).last}',
    );
    debugPrint('[AVATAR DEBUG] Content type: image/jpeg');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authenticatedHeaders(token))
      ..files.add(
        await http.MultipartFile.fromPath(
          'avatar',
          filePath,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

    debugPrint('[AVATAR DEBUG] Request send started.');
    final response = await _sendWithTransportHandling(
      () async => http.Response.fromStream(
        await _httpClient.send(request).timeout(_requestTimeout),
      ),
    );
    debugPrint('[AVATAR DEBUG] HTTP response received.');
    debugPrint('[AVATAR DEBUG] HTTP status code: ${response.statusCode}');
    debugPrint(
      '[AVATAR DEBUG] Response Content-Type header: '
      '${response.headers['content-type']}',
    );
    debugPrint(
      '[AVATAR DEBUG] Response body length: ${response.body.length} chars',
    );
    return _decodeUploadAvatarResponse(response);
  }

  /// Calls `GET /api/business-central/ledger-entries` for the authenticated
  /// user, requesting [page] at a fixed [perPage] size. Never sends a
  /// customer identifier — the ANC API scopes the result to the
  /// authenticated [token] server-side.
  ///
  /// [page] is clamped to `>= 1` and [perPage] to
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// before the request is sent, so a caller-side bug can never grow the
  /// requested page size or send a nonsensical page number.
  Future<PaginatedResponse<LedgerEntry>> fetchLedgerEntries({
    required String token,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.ledgerEntriesPath,
      token: token,
      queryParameters: {'page': '$safePage', 'per_page': '$safePerPage'},
    );
    return _decodeLedgerEntriesResponse(response);
  }

  /// Follows a backend-provided `next_page_url` for the ledger-entries
  /// endpoint (see [PaginatedResponse.nextPageUrl]), preferring it over
  /// reconstructing a `page`/`per_page` query for subsequent pages.
  ///
  /// Rejects [nextPageUrl] with an [ArgumentError] — never sending the
  /// request or attaching the Authorization header — unless it is an
  /// `https` URL whose host is exactly [ApiConfig.baseUrl]'s host. This is
  /// the one guard standing between a compromised/malformed backend
  /// response and the bearer token being sent to an arbitrary host.
  Future<PaginatedResponse<LedgerEntry>> fetchLedgerEntriesPage({
    required String token,
    required Uri nextPageUrl,
  }) async {
    _requireTrustedApiHost(nextPageUrl);

    final response = await _sendWithTransportHandling(
      () => _httpClient
          .get(nextPageUrl, headers: _authenticatedHeaders(token))
          .timeout(_requestTimeout),
    );
    return _decodeLedgerEntriesResponse(response);
  }

  /// Calls `GET /api/business-central/payments` for the authenticated user,
  /// requesting [page] at a fixed [perPage] size. Never sends a customer
  /// identifier — the ANC API scopes the result to the authenticated
  /// [token] server-side.
  ///
  /// [page] is clamped to `>= 1` and [perPage] to
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// before the request is sent, same as [fetchLedgerEntries].
  ///
  /// Deliberately has no `fetchPaymentsPage(nextPageUrl:)` counterpart:
  /// Business Central's `next_page_url` has been observed to drop the
  /// endpoint path (e.g. resolving to `/?page=2`) and cannot be trusted to
  /// preserve `per_page`. Payments pagination is done only by requesting
  /// `page: currentPage + 1` against this fixed endpoint with the original
  /// `perPage` — see `PaymentsService`.
  Future<PaginatedResponse<PaymentEntry>> fetchPayments({
    required String token,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.paymentsPath,
      token: token,
      queryParameters: {'page': '$safePage', 'per_page': '$safePerPage'},
    );
    return _decodePaymentsResponse(response);
  }

  /// Calls `GET /api/business-central/invoices` for the authenticated user,
  /// requesting [page] at a fixed [perPage] size. Never sends a customer
  /// identifier — the ANC API scopes the result to the authenticated
  /// [token] server-side. Each returned row is one invoice *line*, not one
  /// complete invoice — see [BusinessCentralInvoiceLine].
  ///
  /// [page] is clamped to `>= 1` and [perPage] to
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// before the request is sent, same as [fetchLedgerEntries]/[fetchPayments].
  ///
  /// Deliberately has no `fetchInvoicesPage(nextPageUrl:)` counterpart, for
  /// the same reason as [fetchPayments]: the confirmed live envelope's
  /// `next_page_url`/`path` values are unsafe/incomplete (observed as a bare
  /// `/?page=2` / `/`) and must never be used for request construction.
  /// Invoices pagination is done only by requesting `page: currentPage + 1`
  /// against this fixed endpoint with the original `perPage` — see
  /// `InvoicesService`.
  ///
  /// [orderNo], when supplied, is sent as the `order_no` query parameter,
  /// filtering the response to invoice lines whose confirmed `Order_No`
  /// field matches that sales-order `Document_No` — see `OrderDetailScreen`'s
  /// Invoice lookup, the only caller that supplies it. Omitted entirely
  /// (not sent as an empty string) when `null`, so every other caller of
  /// this method — e.g. `InvoicesService`'s unfiltered paging — is
  /// unaffected. Same `item_no`-style pattern as [fetchInventory].
  Future<PaginatedResponse<BusinessCentralInvoiceLine>> fetchInvoices({
    required String token,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
    String? orderNo,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.invoicesPath,
      token: token,
      queryParameters: {
        'page': '$safePage',
        'per_page': '$safePerPage',
        'order_no': ?orderNo,
      },
    );
    return _decodeInvoicesResponse(response);
  }

  /// Calls `GET /api/business-central/sales-orders` for the authenticated
  /// user, requesting [page] at a fixed [perPage] size. Never sends a
  /// customer identifier — the ANC API scopes the result to the
  /// authenticated [token]'s `bc_customer_no` server-side. Each returned row
  /// is one sales-order *line*, not one complete order — see
  /// [BusinessCentralSalesOrderLine]. This is the ANC API's own confirmed
  /// endpoint; never the separate Zebra sales-orders integration.
  ///
  /// [page] is clamped to `>= 1` and [perPage] to
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// before the request is sent, same as [fetchLedgerEntries]/
  /// [fetchPayments]/[fetchInvoices].
  ///
  /// Deliberately has no `fetchSalesOrdersPage(nextPageUrl:)` counterpart,
  /// for the same reason as [fetchPayments]/[fetchInvoices]: this app never
  /// constructs a request from a backend-provided `next_page_url`/
  /// `prev_page_url` for any Business Central list endpoint, to avoid ever
  /// trusting an unverified host from a response body. Sales-orders
  /// pagination is done only by requesting `page: currentPage +/- 1` against
  /// this fixed endpoint with the original `perPage` — see
  /// `SalesOrderLinesService`.
  ///
  /// [documentNo], when supplied, is sent as the `document_no` query
  /// parameter, filtering the response to lines whose `Document_No` matches
  /// that value — see `OrderDetailScreen`'s Order Detail fetch, the only
  /// caller that supplies it. Omitted entirely (not sent as an empty
  /// string) when `null`, so every other caller of this method — e.g.
  /// `SalesOrderLinesService`'s unfiltered paging for the Orders list — is
  /// unaffected. Same `item_no`-style pattern as [fetchInventory].
  Future<PaginatedResponse<BusinessCentralSalesOrderLine>> fetchSalesOrders({
    required String token,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
    String? documentNo,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.salesOrdersPath,
      token: token,
      queryParameters: {
        'page': '$safePage',
        'per_page': '$safePerPage',
        'document_no': ?documentNo,
      },
    );
    return _decodeSalesOrdersResponse(response);
  }

  /// Calls `GET /api/business-central/items` for the authenticated user,
  /// requesting [page] at a fixed [perPage] size. This catalog is
  /// company-scoped rather than user-specific — the ANC API returns the
  /// same rows to every user in the company — but the request still
  /// requires the same Bearer authentication as every other Business
  /// Central endpoint.
  ///
  /// [page] is clamped to `>= 1` and [perPage] to
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// before the request is sent, same as [fetchLedgerEntries]/
  /// [fetchPayments]/[fetchInvoices].
  ///
  /// Deliberately has no `fetchItemsPage(nextPageUrl:)` counterpart, for
  /// the same reason as [fetchPayments]/[fetchInvoices]: the confirmed live
  /// envelope's `next_page_url`/`path` values are unsafe/incomplete
  /// (observed as a bare `/?page=2` / `/`) and must never be used for
  /// request construction. Items pagination is done only by requesting
  /// `page: currentPage + 1` against this fixed endpoint with the original
  /// `perPage` — see `ItemsService`.
  Future<PaginatedResponse<BusinessCentralItem>> fetchItems({
    required String token,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.itemsPath,
      token: token,
      queryParameters: {'page': '$safePage', 'per_page': '$safePerPage'},
    );
    return _decodeItemsResponse(response);
  }

  /// Calls `GET /api/business-central/items` with a `search` query
  /// parameter, requesting [page] at a fixed [perPage] size. Per the
  /// confirmed live contract, supplying `search` changes the endpoint's
  /// response shape from a flat list of [BusinessCentralItem] rows (see
  /// [fetchItems]) to *grouped* rows keyed by `commonItemNo` — see
  /// [BusinessCentralItemSearchGroup]. [fetchItems] itself is untouched and
  /// must never be reused for a search request.
  ///
  /// [search] is sent exactly as given (already trimmed by the caller —
  /// see `ItemCatalogueSearchService`) via [getAuthenticatedJson]'s
  /// percent-encoded `queryParameters`, so a space or other special
  /// character is never manually concatenated into the query string.
  ///
  /// [page]/[perPage] are clamped the same way as [fetchItems]/
  /// [fetchInventory]/every other Business Central list call on this
  /// client.
  Future<PaginatedResponse<BusinessCentralItemSearchGroup>> searchItems({
    required String token,
    required String search,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.itemsPath,
      token: token,
      queryParameters: {
        'search': search,
        'page': '$safePage',
        'per_page': '$safePerPage',
      },
    );

    return _decodeItemSearchResponse(response);
  }

  /// Calls `GET /api/business-central/inventory` for the authenticated
  /// user, requesting [page] at a fixed [perPage] size, filtered to the
  /// exact Business Central item [itemNo]. Like [fetchItems], this data is
  /// company-scoped rather than user-specific, but the request still
  /// requires the same Bearer authentication as every other Business Central
  /// endpoint. Never sends a customer identifier.
  ///
  /// [page] is clamped to `>= 1` and [perPage] to
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// before the request is sent, same as [fetchLedgerEntries]/
  /// [fetchPayments]/[fetchInvoices]/[fetchItems].
  ///
  /// [itemNo] is REQUIRED per the confirmed contract: `GET
  /// /api/business-central/inventory` now rejects a missing `item_no` with
  /// HTTP 422. Sent as-is (not trimmed — trimming/emptiness is the calling
  /// service's boundary responsibility, same as [searchItems]'s [search]) as
  /// the `item_no` query parameter via [getAuthenticatedJson]'s
  /// `queryParameters` (backed by [Uri.replace]), never by manual string
  /// concatenation, so a value containing a space, hyphen, or slash is
  /// percent-encoded safely. A blank (empty or whitespace-only) [itemNo]
  /// throws [ArgumentError] instead of silently sending an empty/omitted
  /// `item_no` — this method must never generate an unfiltered inventory
  /// request.
  ///
  /// Deliberately has no `fetchInventoryPage(nextPageUrl:)` counterpart, for
  /// the same reason as [fetchItems]: a live response for this endpoint is
  /// not yet available, and every other Business Central list endpoint's
  /// confirmed live `next_page_url`/`path` values have been unsafe/incomplete
  /// (observed as a bare `/?page=2` / `/`). Inventory pagination is done
  /// only by requesting `page: currentPage + 1` against this fixed endpoint
  /// with the original `perPage` — see `InventoryService`/
  /// `ApiStockLookupService`.
  Future<PaginatedResponse<BusinessCentralInventoryEntry>> fetchInventory({
    required String token,
    required String itemNo,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async {
    if (itemNo.trim().isEmpty) {
      throw ArgumentError.value(itemNo, 'itemNo', 'must not be blank');
    }

    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.inventoryPath,
      token: token,
      queryParameters: {
        'page': '$safePage',
        'per_page': '$safePerPage',
        'item_no': itemNo,
      },
    );
    return _decodeInventoryResponse(response);
  }

  /// Calls `GET /api/business-central/purchase-orders` for the
  /// authenticated user, requesting [page] at a fixed [perPage] size,
  /// optionally filtered to the exact Business Central item [itemNo] via
  /// the `item_no` query parameter (applied server-side over the ANC API's
  /// normalized rows). Company-wide procurement data — never sends a
  /// customer identifier; vendor and cost fields are stripped server-side
  /// before rows reach this client.
  ///
  /// [page]/[perPage] are clamped the same way as every other Business
  /// Central list call on this client, and pagination follows the same
  /// fixed-endpoint `page: currentPage + 1` convention (never a
  /// backend-provided `next_page_url`).
  ///
  /// A blank (empty or whitespace-only) [itemNo] throws [ArgumentError]
  /// rather than silently sending an unfiltered request — the only caller
  /// today ([ApiStockLookupService]) always filters; pass `null` explicitly
  /// for a deliberate unfiltered fetch.
  Future<PaginatedResponse<PurchaseOrderLine>> fetchPurchaseOrders({
    required String token,
    String? itemNo,
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
  }) async {
    if (itemNo != null && itemNo.trim().isEmpty) {
      throw ArgumentError.value(itemNo, 'itemNo', 'must not be blank');
    }

    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(
      ApiConfig.businessCentralMinPerPage,
      ApiConfig.businessCentralMaxPerPage,
    );

    final response = await getAuthenticatedJson(
      ApiConfig.purchaseOrdersPath,
      token: token,
      queryParameters: {
        'page': '$safePage',
        'per_page': '$safePerPage',
        'item_no': ?itemNo,
      },
    );
    return _decodePurchaseOrdersResponse(response);
  }

  /// Calls `GET /api/business-central/customer-details` for the
  /// authenticated user. Never sends a customer identifier — the ANC API
  /// scopes the result to the authenticated [token] server-side. Not
  /// paginated: returns one [CustomerDetails] snapshot, never a
  /// [PaginatedResponse].
  ///
  /// [dateFrom]/[dateTo], when supplied, are sent as the `date_from`/
  /// `date_to` query parameters, each formatted as `yyyy-MM-dd` — the same
  /// date-only format this client's other Business Central date fields
  /// (`Posting_Date`/`Due_Date`/`postingDate`/`dueDate`) already use. Either
  /// or both may be omitted (both are documented as optional); an omitted
  /// date is never sent as an empty string.
  Future<CustomerDetails> fetchCustomerDetails({
    required String token,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final formattedDateFrom = dateFrom == null
        ? null
        : _formatDateOnly(dateFrom);
    final formattedDateTo = dateTo == null ? null : _formatDateOnly(dateTo);

    final response = await getAuthenticatedJson(
      ApiConfig.customerDetailsPath,
      token: token,
      queryParameters: {
        'date_from': ?formattedDateFrom,
        'date_to': ?formattedDateTo,
      },
    );
    return _decodeCustomerDetailsResponse(response);
  }

  /// Formats [date] as `yyyy-MM-dd`, matching every other date-only field
  /// this client sends/parses.
  static String _formatDateOnly(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-'
        '${twoDigits(date.month)}-${twoDigits(date.day)}';
  }

  /// Calls `POST /api/auth/logout` with the given [token] as a Bearer
  /// credential, revoking the current Sanctum personal access token
  /// server-side. Sends no request body and no customer identifier — only
  /// the shared `Accept` header and the `Authorization` header built by
  /// [_authenticatedHeaders], the same as every other authenticated call in
  /// this client.
  ///
  /// The confirmed response is `{"message": "Logged out."}`; [message] is
  /// decoded only far enough to confirm the response shape (a JSON object
  /// with a String `message`) and is not otherwise inspected, returned, or
  /// persisted — callers never need to display or store it.
  ///
  /// A non-2xx response raises [AncHttpException] with that status code,
  /// exactly like every other endpoint on this client — this method does
  /// not special-case 401/502/503 itself; that judgment belongs to the
  /// caller (see `AuthService.logout`).
  Future<void> logout({required String token}) async {
    final uri = _resolve(ApiConfig.logoutPath);

    final response = await _sendWithTransportHandling(
      () => _httpClient
          .post(uri, headers: _authenticatedHeaders(token))
          .timeout(_requestTimeout),
    );
    _decodeLogoutResponse(response);
  }

  /// Calls `PUT /api/auth/me/password` with the given [token] as a Bearer
  /// credential, changing the authenticated user's password. Sends exactly
  /// the three fields the confirmed contract requires — never trimmed or
  /// otherwise modified, the same as [LoginRequest.password].
  ///
  /// The confirmed contract does not document a response body shape, so
  /// [_decodeChangePasswordResponse] only checks for HTTP 200 (see its doc
  /// comment) rather than assuming one. Per the contract, this endpoint
  /// does not rotate or revoke the current bearer [token] — callers must
  /// not treat a successful call as invalidating it.
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final response = await putAuthenticatedJson(ApiConfig.mePasswordPath, {
      'current_password': currentPassword,
      'password': password,
      'password_confirmation': passwordConfirmation,
    }, token: token);
    _decodeChangePasswordResponse(response);
  }

  /// Throws an [ArgumentError] unless [url] is `https` and its host is
  /// exactly [ApiConfig.baseUrl]'s host — see [fetchLedgerEntriesPage].
  void _requireTrustedApiHost(Uri url) {
    if (url.scheme != 'https' || url.host != ApiConfig.baseUrl.host) {
      throw ArgumentError.value(
        url,
        'nextPageUrl',
        'must be an https URL on the ANC API host (${ApiConfig.baseUrl.host})',
      );
    }
  }

  /// Sends an unauthenticated POST request with a JSON body to
  /// [relativePath], resolved against [ApiConfig.baseUrl]. Never attaches
  /// an Authorization header — this method is for the ANC API's public
  /// endpoints only.
  ///
  /// [relativePath] must be a plain relative path (e.g. `api/auth/login`):
  /// no absolute URL, protocol-relative path, leading slash, backslash,
  /// `.`/`..` path-traversal segment (including percent-encoded forms),
  /// query string, or fragment. Any of these raise an [ArgumentError]
  /// before any request is sent, so a caller can never change the
  /// request's origin (scheme, host, or port) through crafted path input.
  Future<http.Response> postPublicJson(
    String relativePath,
    Map<String, dynamic> body,
  ) async {
    final uri = _resolve(relativePath);
    final encodedBody = jsonEncode(body);

    return _sendWithTransportHandling(
      () => _httpClient
          .post(uri, headers: _sharedHeaders, body: encodedBody)
          .timeout(_requestTimeout),
    );
  }

  /// Sends an authenticated GET request to [relativePath], resolved against
  /// [ApiConfig.baseUrl], with `Authorization: Bearer <token>` and
  /// `Accept: application/json` — the only place in this app those headers
  /// are constructed. Same [relativePath] safety rules as [postPublicJson].
  ///
  /// [queryParameters], when supplied, is attached as a percent-encoded
  /// query string after [relativePath] has already passed every path-safety
  /// check — it can never be used to change the request's scheme, host, or
  /// port, and every key/value is escaped with [Uri.encodeComponent] before
  /// being joined, so a value containing `&`, `=`, `%`, `+`, a space, a
  /// slash, or a non-ASCII character can never be manually concatenated
  /// into — or corrupt the structure of — the query string.
  ///
  /// Deliberately built this way instead of `Uri.replace(queryParameters:)`,
  /// which encodes a space as `+` (the `application/x-www-form-urlencoded`
  /// convention): the confirmed ANC API contract for a value that may
  /// contain a literal space (see `AncApiClient.fetchInventory`'s
  /// `item_no`) is percent-encoding, e.g. `item_no=1038%2001`. Applying this
  /// to every authenticated GET (not a filtered-inventory-only special
  /// case) keeps exactly one query-building path for this client; every
  /// other caller's values so far are plain digits (`page`/`per_page`),
  /// which [Uri.encodeComponent] passes through unchanged, so this is not a
  /// behavior change for them. [Uri.replace]'s `query:` parameter takes an
  /// already-encoded string as-is — it does not re-encode it — so this can
  /// never double-encode a value.
  Future<http.Response> getAuthenticatedJson(
    String relativePath, {
    required String token,
    Map<String, String>? queryParameters,
  }) async {
    var uri = _resolve(relativePath);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final query = queryParameters.entries
          .map(
            (entry) =>
                '${Uri.encodeComponent(entry.key)}='
                '${Uri.encodeComponent(entry.value)}',
          )
          .join('&');
      uri = uri.replace(query: query);
    }

    return _sendWithTransportHandling(
      () => _httpClient
          .get(uri, headers: _authenticatedHeaders(token))
          .timeout(_requestTimeout),
    );
  }

  /// Sends an authenticated PATCH request with a JSON [body] to
  /// [relativePath], resolved against [ApiConfig.baseUrl], with
  /// `Authorization: Bearer <token>` (via [_authenticatedHeaders]) plus
  /// `Content-Type: application/json`. Same [relativePath] safety rules as
  /// [postPublicJson]/[getAuthenticatedJson].
  Future<http.Response> patchAuthenticatedJson(
    String relativePath,
    Map<String, dynamic> body, {
    required String token,
  }) async {
    final uri = _resolve(relativePath);
    final encodedBody = jsonEncode(body);

    return _sendWithTransportHandling(
      () => _httpClient
          .patch(
            uri,
            headers: _authenticatedJsonHeaders(token),
            body: encodedBody,
          )
          .timeout(_requestTimeout),
    );
  }

  /// Sends an authenticated PUT request with a JSON [body] to
  /// [relativePath], resolved against [ApiConfig.baseUrl], with the same
  /// headers as [patchAuthenticatedJson]. Same [relativePath] safety rules
  /// as [postPublicJson]/[getAuthenticatedJson].
  Future<http.Response> putAuthenticatedJson(
    String relativePath,
    Map<String, dynamic> body, {
    required String token,
  }) async {
    final uri = _resolve(relativePath);
    final encodedBody = jsonEncode(body);

    return _sendWithTransportHandling(
      () => _httpClient
          .put(
            uri,
            headers: _authenticatedJsonHeaders(token),
            body: encodedBody,
          )
          .timeout(_requestTimeout),
    );
  }

  /// The one place `Authorization: Bearer ...` is built, so it can never be
  /// duplicated or drift across call sites. Never logs or otherwise exposes
  /// [token].
  static Map<String, String> _authenticatedHeaders(String token) => {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// [_authenticatedHeaders] plus `Content-Type: application/json`, for the
  /// authenticated requests that carry a JSON body ([patchAuthenticatedJson],
  /// [putAuthenticatedJson]) — a plain authenticated GET must never send
  /// this header (see the class doc comment).
  static Map<String, String> _authenticatedJsonHeaders(String token) => {
    ..._authenticatedHeaders(token),
    'Content-Type': 'application/json',
  };

  /// Runs [send], normalizing transport/protocol-level failures the same
  /// way for every request method — shared by [postPublicJson] and
  /// [getAuthenticatedJson] so that mapping is defined exactly once.
  Future<http.Response> _sendWithTransportHandling(
    Future<http.Response> Function() send,
  ) async {
    try {
      return await send();
    } on AncApiException {
      rethrow;
    } on TimeoutException {
      throw const AncNetworkException('The ANC API did not respond in time.');
    } on http.ClientException catch (error) {
      throw AncNetworkException(
        'Could not reach the ANC API: ${error.message}',
      );
    } on SocketException catch (error) {
      throw AncNetworkException(
        'Could not reach the ANC API: ${error.message}',
      );
    }
  }

  Uri _resolve(String relativePath) {
    final rejection = _rejectionReasonFor(relativePath);
    if (rejection != null) {
      throw ArgumentError.value(relativePath, 'relativePath', rejection);
    }

    final base = ApiConfig.baseUrl;
    final combinedPath = '${base.path}/$relativePath'.replaceAll(
      RegExp(r'/{2,}'),
      '/',
    );
    final resolved = base.replace(path: combinedPath);

    if (resolved.origin != base.origin) {
      // Defense in depth: the construction above can never actually
      // produce a different origin, but this guarantees it structurally
      // rather than by convention alone.
      throw StateError('Resolved URI origin diverged from ApiConfig.baseUrl.');
    }
    return resolved;
  }

  /// Returns a human-readable rejection reason if [relativePath] is not a
  /// plain, safe relative ANC API path, or `null` if it is acceptable.
  String? _rejectionReasonFor(String relativePath) {
    if (relativePath.isEmpty) {
      return 'relativePath must not be empty.';
    }
    if (relativePath.startsWith('/')) {
      return 'relativePath must not start with "/" (only relative paths '
          'are accepted).';
    }
    if (relativePath.contains('\\')) {
      return 'relativePath must not contain a backslash.';
    }

    final parsed = Uri.parse(relativePath);
    if (parsed.hasScheme || parsed.hasAuthority) {
      return 'relativePath must not be an absolute URL or specify a host.';
    }
    if (parsed.hasQuery) {
      return 'relativePath must not include a query string (not yet '
          'supported).';
    }
    if (parsed.hasFragment) {
      return 'relativePath must not include a fragment (never sent to '
          'the server).';
    }

    final String decoded;
    try {
      decoded = Uri.decodeComponent(relativePath);
    } on FormatException {
      return 'relativePath contains malformed percent-encoding.';
    } on ArgumentError {
      // Uri.decodeComponent throws ArgumentError (not FormatException) for
      // a truncated/invalid percent-escape sequence.
      return 'relativePath contains malformed percent-encoding.';
    }
    final segments = decoded.split('/');
    if (segments.contains('..') || segments.contains('.')) {
      return 'relativePath must not contain "." or ".." path segments.';
    }

    return null;
  }

  LoginResponse _decodeLoginResponse(http.Response response) {
    if (response.statusCode == 200) {
      final json = _decodeJsonMap(response.body);
      try {
        return LoginResponse.fromJson(json);
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed login response: ${error.message}',
        );
      }
    }

    if (response.statusCode == 422) {
      throw AncHttpException(
        'ANC API rejected the login request.',
        statusCode: 422,
        validationError: ApiValidationError.fromJson(
          _decodeJsonOrNull(response.body),
        ),
      );
    }

    throw AncHttpException(
      'ANC API login request failed.',
      statusCode: response.statusCode,
    );
  }

  /// Decodes a `GET /auth/me` response, requiring the top-level `data`
  /// wrapper the ANC API always sends for this endpoint — a body shaped
  /// like a login response (or any other shape) is a protocol failure, not
  /// a successfully parsed user. HTTP 401 surfaces as [AncHttpException]
  /// with `statusCode: 401` like every other non-2xx status, so callers
  /// decide how to react (see `AuthService.confirmSession`) rather than
  /// this client special-casing session semantics.
  AuthenticatedUser _decodeCurrentUserResponse(http.Response response) {
    if (response.statusCode == 200) {
      final json = _decodeJsonMap(response.body);
      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        throw const AncProtocolException(
          'Malformed /auth/me response: missing the required "data" wrapper.',
        );
      }
      try {
        return AuthenticatedUser.fromJson(data);
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed /auth/me response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API /auth/me request failed.',
      statusCode: response.statusCode,
    );
  }

  /// Decodes a `PATCH /auth/me` response. HTTP 200 requires the same
  /// top-level `data` wrapper as [_decodeCurrentUserResponse]. Unlike that
  /// method, every other status parses [ApiValidationError] for a 422 body
  /// — [AuthService.updateProfile] needs `errors.username`/`errors.phone`
  /// to distinguish a taken username from an invalid phone.
  AuthenticatedUser _decodeUpdateMeResponse(http.Response response) {
    if (response.statusCode == 200) {
      final json = _decodeJsonMap(response.body);
      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        throw const AncProtocolException(
          'Malformed /auth/me update response: missing the required "data" '
          'wrapper.',
        );
      }
      try {
        return AuthenticatedUser.fromJson(data);
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed /auth/me update response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API /auth/me update request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes a `POST /auth/me/avatar` response. Same shape as
  /// [_decodeUpdateMeResponse] — HTTP 200 requires the top-level `data`
  /// wrapper, and every other status parses [ApiValidationError] for a 422
  /// body so `AuthService.uploadAvatar` can surface `errors.avatar`.
  AuthenticatedUser _decodeUploadAvatarResponse(http.Response response) {
    _logAvatarResponseStructure(response.body);

    if (response.statusCode == 200) {
      final json = _decodeJsonMap(response.body);
      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[AVATAR DEBUG] Parsing AuthenticatedUser succeeded: false '
          '(missing/invalid "data" wrapper).',
        );
        throw const AncProtocolException(
          'Malformed /auth/me/avatar response: missing the required "data" '
          'wrapper.',
        );
      }
      try {
        final user = AuthenticatedUser.fromJson(data);
        debugPrint('[AVATAR DEBUG] Parsing AuthenticatedUser succeeded: true.');
        return user;
      } on FormatException catch (error) {
        debugPrint(
          '[AVATAR DEBUG] Parsing AuthenticatedUser succeeded: false '
          '(${error.message}).',
        );
        throw AncProtocolException(
          'Malformed /auth/me/avatar response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API avatar-upload request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Temporary diagnostic-only helper for the profile-avatar investigation:
  /// a best-effort, side-effect-free look at an `/auth/me/avatar` response
  /// body's *shape* — never its values (beyond `avatar_url`'s type) — so we
  /// can tell whether production's response actually matches the assumed
  /// `{"data": {..., "avatar_url": ...}}` envelope. Never throws and never
  /// influences [_decodeUploadAvatarResponse]'s return value or the
  /// exception it raises; [_decodeJsonMap]/[AuthenticatedUser.fromJson]
  /// remain the only source of truth for parsing.
  void _logAvatarResponseStructure(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      debugPrint(
        '[AVATAR DEBUG] Response JSON decoding failed: ${error.runtimeType}.',
      );
      final truncated = body.length > 300 ? '${body.substring(0, 300)}…' : body;
      debugPrint('[AVATAR DEBUG] Response body (truncated): $truncated');
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      debugPrint(
        '[AVATAR DEBUG] Response JSON top-level type: '
        '${decoded.runtimeType} (expected a JSON object).',
      );
      return;
    }

    debugPrint('[AVATAR DEBUG] Response top-level keys: ${decoded.keys}');
    final hasData = decoded.containsKey('data');
    final data = decoded['data'];
    debugPrint('[AVATAR DEBUG] Response "data" key exists: $hasData');
    debugPrint(
      '[AVATAR DEBUG] Response "data" is a Map: '
      '${data is Map<String, dynamic>}',
    );
    if (data is Map<String, dynamic>) {
      debugPrint('[AVATAR DEBUG] Response "data" keys: ${data.keys}');
      debugPrint(
        '[AVATAR DEBUG] Response "avatar_url" exists: '
        '${data.containsKey('avatar_url')}',
      );
      debugPrint(
        '[AVATAR DEBUG] Response "avatar_url" type: '
        '${data['avatar_url']?.runtimeType}',
      );
    }
  }

  /// Decodes a ledger-entries response. HTTP 200 is parsed as a
  /// [PaginatedResponse] of [LedgerEntry]; every other status raises
  /// [AncHttpException] with that [statusCode] — including a parsed
  /// [ApiValidationError] for 422, since the Business Central taxonomy
  /// (pagination bug vs. account-not-linked) is decided one layer up (see
  /// `mapBusinessCentralError`), not here. This client stays
  /// transport/protocol-only.
  PaginatedResponse<LedgerEntry> _decodeLedgerEntriesResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<LedgerEntry>.fromJson(
          json,
          LedgerEntry.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed ledger-entries response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API ledger-entries request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes a payments response. HTTP 200 is parsed as a
  /// [PaginatedResponse] of [PaymentEntry]; every other status raises
  /// [AncHttpException] with that [statusCode] — including a parsed
  /// [ApiValidationError] for 422 — the same shape as
  /// [_decodeLedgerEntriesResponse]. The Business Central taxonomy
  /// (pagination bug vs. account-not-linked) is decided one layer up (see
  /// `mapBusinessCentralError`), not here.
  PaginatedResponse<PaymentEntry> _decodePaymentsResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<PaymentEntry>.fromJson(
          json,
          PaymentEntry.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed payments response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API payments request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes an invoices response. HTTP 200 is parsed as a
  /// [PaginatedResponse] of [BusinessCentralInvoiceLine]; every other status
  /// raises [AncHttpException] with that [statusCode] — including a parsed
  /// [ApiValidationError] for 422 — the same shape as
  /// [_decodePaymentsResponse]/[_decodeLedgerEntriesResponse]. The Business
  /// Central taxonomy (pagination bug vs. account-not-linked) is decided one
  /// layer up (see `mapBusinessCentralError`), not here.
  PaginatedResponse<BusinessCentralInvoiceLine> _decodeInvoicesResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<BusinessCentralInvoiceLine>.fromJson(
          json,
          BusinessCentralInvoiceLine.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed invoices response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API invoices request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes a sales-orders response. HTTP 200 is parsed as a
  /// [PaginatedResponse] of [BusinessCentralSalesOrderLine]; every other
  /// status raises [AncHttpException] with that [statusCode] — including a
  /// parsed [ApiValidationError] for 422 — the same shape as
  /// [_decodeInvoicesResponse]/[_decodePaymentsResponse]/
  /// [_decodeLedgerEntriesResponse]. The Business Central taxonomy
  /// (pagination bug vs. account-not-linked) is decided one layer up (see
  /// `mapBusinessCentralError`), not here.
  PaginatedResponse<PurchaseOrderLine> _decodePurchaseOrdersResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<PurchaseOrderLine>.fromJson(
          json,
          PurchaseOrderLine.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed purchase-orders response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API purchase-orders request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  PaginatedResponse<BusinessCentralSalesOrderLine> _decodeSalesOrdersResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<BusinessCentralSalesOrderLine>.fromJson(
          json,
          BusinessCentralSalesOrderLine.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed sales-orders response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API sales-orders request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes an items response. HTTP 200 is parsed as a [PaginatedResponse]
  /// of [BusinessCentralItem]; every other status raises [AncHttpException]
  /// with that [statusCode] — including a parsed [ApiValidationError] for
  /// 422 — the same shape as [_decodeInvoicesResponse]/
  /// [_decodePaymentsResponse]/[_decodeLedgerEntriesResponse]. The Business
  /// Central taxonomy (pagination bug vs. some other 422 cause) is decided
  /// one layer up (see `mapBusinessCentralError`), not here.
  PaginatedResponse<BusinessCentralItem> _decodeItemsResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<BusinessCentralItem>.fromJson(
          json,
          BusinessCentralItem.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed items response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API items request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes a `search`-scoped items response. HTTP 200 is parsed as a
  /// [PaginatedResponse] of [BusinessCentralItemSearchGroup] — the grouped
  /// shape this endpoint returns only when a `search` query parameter was
  /// sent (see [searchItems]) — never [BusinessCentralItem]. Every other
  /// status raises [AncHttpException] with that [statusCode] — including a
  /// parsed [ApiValidationError] for 422 — the same shape as
  /// [_decodeItemsResponse].
  PaginatedResponse<BusinessCentralItemSearchGroup> _decodeItemSearchResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<BusinessCentralItemSearchGroup>.fromJson(
          json,
          BusinessCentralItemSearchGroup.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed item search response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API item search request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes an inventory response. HTTP 200 is parsed as a
  /// [PaginatedResponse] of [BusinessCentralInventoryEntry]; every other
  /// status raises [AncHttpException] with that [statusCode] — including a
  /// parsed [ApiValidationError] for 422 — the same shape as
  /// [_decodeItemsResponse]. The Business Central taxonomy (pagination bug
  /// vs. some other 422 cause) is decided one layer up (see
  /// `mapBusinessCentralError`), not here.
  PaginatedResponse<BusinessCentralInventoryEntry> _decodeInventoryResponse(
    http.Response response,
  ) {
    if (response.statusCode == 200) {
      final json = _decodeJsonOrThrow(response.body);
      try {
        return PaginatedResponse<BusinessCentralInventoryEntry>.fromJson(
          json,
          BusinessCentralInventoryEntry.fromJson,
        );
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed inventory response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API inventory request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes a customer-details response. HTTP 200 is parsed as a single
  /// [CustomerDetails] snapshot — never a [PaginatedResponse], since this
  /// endpoint is not paginated; every other status raises [AncHttpException]
  /// with that [statusCode] — including a parsed [ApiValidationError] for
  /// 422 — the same shape as every other Business Central endpoint on this
  /// client. The Business Central taxonomy (account-not-linked vs. some
  /// other 422 cause) is decided one layer up (see `mapBusinessCentralError`),
  /// not here.
  CustomerDetails _decodeCustomerDetailsResponse(http.Response response) {
    if (response.statusCode == 200) {
      final json = _decodeJsonMap(response.body);
      try {
        return CustomerDetails.fromJson(json);
      } on FormatException catch (error) {
        throw AncProtocolException(
          'Malformed customer-details response: ${error.message}',
        );
      }
    }

    throw AncHttpException(
      'ANC API customer-details request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  /// Decodes a logout response. HTTP 200 requires a JSON object with a
  /// String `message` field — anything else (non-object JSON, malformed
  /// JSON, a missing/non-String `message`) raises [AncProtocolException].
  /// Every other status raises [AncHttpException] with that [statusCode],
  /// with no [ApiValidationError] parsing — this endpoint has no documented
  /// 422 validation shape.
  void _decodeLogoutResponse(http.Response response) {
    if (response.statusCode == 200) {
      final json = _decodeJsonMap(response.body);
      final message = json['message'];
      if (message is! String) {
        throw const AncProtocolException(
          'Malformed logout response: "message" missing or not a String.',
        );
      }
      return;
    }

    throw AncHttpException(
      'ANC API logout request failed.',
      statusCode: response.statusCode,
    );
  }

  /// Decodes a `PUT /auth/me/password` response. The confirmed contract
  /// does not document a response body shape (unlike [_decodeLogoutResponse]'s
  /// confirmed `{"message": ...}` shape), so this only requires HTTP 200 —
  /// the body, whatever it contains, is not parsed or inspected. Every
  /// other status raises [AncHttpException] with that [statusCode],
  /// including a parsed [ApiValidationError] for 422 — `AuthService`
  /// distinguishes `errors.current_password` from
  /// `errors.password`/`errors.password_confirmation`.
  void _decodeChangePasswordResponse(http.Response response) {
    if (response.statusCode == 200) return;

    throw AncHttpException(
      'ANC API password-change request failed.',
      statusCode: response.statusCode,
      validationError: response.statusCode == 422
          ? ApiValidationError.fromJson(_decodeJsonOrNull(response.body))
          : null,
    );
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final json = _decodeJsonOrThrow(body);
    if (json is! Map<String, dynamic>) {
      throw const AncProtocolException(
        'Expected a JSON object in the ANC API response.',
      );
    }
    return json;
  }

  Object? _decodeJsonOrThrow(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AncProtocolException('ANC API response was not valid JSON.');
    }
  }

  Object? _decodeJsonOrNull(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Closes the underlying [http.Client], but only when this instance
  /// created it; a caller-supplied client (as tests inject) is left open
  /// for the caller to manage.
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
