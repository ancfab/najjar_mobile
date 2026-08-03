import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth/api_validation_error.dart';
import '../models/auth/authenticated_user.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';
import '../models/business_central/business_central_inventory_entry.dart';
import '../models/business_central/business_central_invoice_line.dart';
import '../models/business_central/business_central_item.dart';
import '../models/business_central/ledger_entry.dart';
import '../models/business_central/paginated_response.dart';
import '../models/business_central/payment_entry.dart';
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
  Future<PaginatedResponse<BusinessCentralInvoiceLine>> fetchInvoices({
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
      ApiConfig.invoicesPath,
      token: token,
      queryParameters: {'page': '$safePage', 'per_page': '$safePerPage'},
    );
    return _decodeInvoicesResponse(response);
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

  /// Calls `GET /api/business-central/inventory` for the authenticated
  /// user, requesting [page] at a fixed [perPage] size. Like [fetchItems],
  /// this data is company-scoped rather than user-specific, but the request
  /// still requires the same Bearer authentication as every other Business
  /// Central endpoint. Never sends a customer identifier.
  ///
  /// [page] is clamped to `>= 1` and [perPage] to
  /// `[ApiConfig.businessCentralMinPerPage, ApiConfig.businessCentralMaxPerPage]`
  /// before the request is sent, same as [fetchLedgerEntries]/
  /// [fetchPayments]/[fetchInvoices]/[fetchItems].
  ///
  /// [itemNo], when supplied, is sent as the `item_no` query parameter,
  /// filtering the response to that exact Business Central item — see
  /// `ApiStockLookupService`, the only caller that supplies it. Sent via
  /// [getAuthenticatedJson]'s `queryParameters` (backed by [Uri.replace]),
  /// never by manual string concatenation, so a value containing a space,
  /// hyphen, or slash is percent-encoded safely. Omitted entirely (not sent
  /// as an empty string) when `null`, so every other caller of this method
  /// — e.g. `InventoryService`'s unfiltered paging — is unaffected.
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
    int page = 1,
    int perPage = ApiConfig.businessCentralDefaultPerPage,
    String? itemNo,
  }) async {
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
        'item_no': ?itemNo,
      },
    );
    return _decodeInventoryResponse(response);
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

  /// The one place `Authorization: Bearer ...` is built, so it can never be
  /// duplicated or drift across call sites. Never logs or otherwise exposes
  /// [token].
  static Map<String, String> _authenticatedHeaders(String token) => {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
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
