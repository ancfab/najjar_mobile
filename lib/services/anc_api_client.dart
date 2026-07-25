import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth/api_validation_error.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';
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
/// a Bearer token. A later phase adding authenticated requests must
/// introduce a distinctly-named method (e.g. `postAuthenticatedJson`) that
/// requires a token argument, rather than adding an optional parameter
/// here that a caller could accidentally omit.
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

    try {
      return await _httpClient
          .post(uri, headers: _sharedHeaders, body: encodedBody)
          .timeout(_requestTimeout);
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
