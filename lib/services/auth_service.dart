import '../config/api_config.dart';
import '../models/auth/auth_session.dart';
import '../models/auth/login_failure.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'secure_auth_session_store.dart';
import 'session_storage_exception.dart';

/// Purpose: Coordinates authentication against the ANC API and persists the
/// resulting secure session.
///
/// Responsibilities:
/// - Build the exact `POST /api/auth/login` request from caller-supplied
///   values plus the fixed [ApiConfig.clientId].
/// - Call the login endpoint through [AncApiClient] and map its typed
///   failures — and the secure-storage failure that can follow a successful
///   call — into the small stable [AuthLoginFailureType] taxonomy.
/// - Persist the resulting [AuthSession] through [AuthSessionStore] and
///   return [AuthLoginSuccess] only once that persistence has completed.
///
/// Must not:
/// - Contain navigation or widget logic.
/// - Store or log passwords, tokens, or raw API responses.
/// - Communicate directly with Business Central.
/// - Attempt authenticated (Bearer) requests, HTTP 401 handling, token
///   refresh, or backend logout — none of that exists yet.
class AuthService {
  /// Creates an [AuthService] over caller-owned dependencies. [apiClient]
  /// and [sessionStore] are never closed or otherwise disposed by this
  /// instance — the caller retains ownership.
  AuthService({
    required AncApiClient apiClient,
    required AuthSessionStore sessionStore,
  }) : _apiClient = apiClient,
       _sessionStore = sessionStore,
       _ownsApiClient = false;

  AuthService._owned({
    required AncApiClient apiClient,
    required AuthSessionStore sessionStore,
  }) : _apiClient = apiClient,
       _sessionStore = sessionStore,
       _ownsApiClient = true;

  /// Production factory: creates and owns its own [AncApiClient] (closed by
  /// [close]) over the real network, and defaults to a real
  /// [SecureAuthSessionStore] unless [sessionStore] is supplied.
  factory AuthService.production({AuthSessionStore? sessionStore}) =>
      AuthService._owned(
        apiClient: AncApiClient(),
        sessionStore: sessionStore ?? SecureAuthSessionStore(),
      );

  final AncApiClient _apiClient;
  final AuthSessionStore _sessionStore;

  /// Whether this instance created [_apiClient] itself (via
  /// [AuthService.production]) as opposed to receiving a caller-owned one —
  /// only an owned client is closed by [close].
  final bool _ownsApiClient;

  /// Logs in against the ANC API and, on success, persists the resulting
  /// session before returning.
  ///
  /// [country], [phone], and [username] are sent as already
  /// selected/constructed API values — this method does not validate them
  /// against the ANC API's country/dial-code catalogue. [country] and
  /// [username] have accidental outer whitespace trimmed; [phone] and
  /// [password] are sent exactly as supplied, unmodified. The distributor
  /// `client_id` always comes from [ApiConfig.clientId] and cannot be
  /// overridden by the caller.
  Future<AuthLoginResult> login({
    required String country,
    required String phone,
    required String username,
    required String password,
  }) async {
    final trimmedCountry = country.trim();
    final trimmedUsername = username.trim();

    if (trimmedCountry.isEmpty ||
        phone.isEmpty ||
        trimmedUsername.isEmpty ||
        password.isEmpty) {
      return const AuthLoginFailure(AuthLoginFailureType.invalidInput);
    }

    final request = LoginRequest(
      country: trimmedCountry,
      phone: phone,
      username: trimmedUsername,
      clientId: ApiConfig.clientId,
      password: password,
    );

    final LoginResponse response;
    try {
      response = await _apiClient.login(request);
    } on AncHttpException catch (error) {
      return _mapHttpFailure(error);
    } on AncNetworkException {
      return const AuthLoginFailure(AuthLoginFailureType.network);
    } on AncProtocolException {
      return const AuthLoginFailure(AuthLoginFailureType.invalidResponse);
    }

    final session = AuthSession.fromLoginResponse(response);

    try {
      await _sessionStore.save(session);
    } on SessionStorageException {
      return const AuthLoginFailure(AuthLoginFailureType.secureStorage);
    }

    return AuthLoginSuccess(session);
  }

  /// Maps a well-formed non-2xx login response to a failure.
  ///
  /// Deterministic rule: HTTP 422 with an `errors.phone` message maps to
  /// [AuthLoginFailureType.invalidPhone]; every other 422 shape (including
  /// `errors.username`, an unknown field, or a malformed/empty body) maps
  /// neutrally to [AuthLoginFailureType.invalidCredentials] — the ANC API
  /// deliberately surfaces wrong password, unknown username/phone, a
  /// deactivated account, and backend misconfiguration identically under
  /// `errors.username`, so none of those can be distinguished or implied
  /// here. HTTP 5xx, and every other unexpected non-success status
  /// (including an unexpected 401 — this endpoint has no session to clear),
  /// map to [AuthLoginFailureType.serviceUnavailable].
  AuthLoginFailure _mapHttpFailure(AncHttpException error) {
    if (error.statusCode == 422) {
      final phoneError = error.validationError?.firstErrorFor('phone');
      if (phoneError != null) {
        return AuthLoginFailure(
          AuthLoginFailureType.invalidPhone,
          phoneError: phoneError,
        );
      }
      return const AuthLoginFailure(AuthLoginFailureType.invalidCredentials);
    }

    return const AuthLoginFailure(AuthLoginFailureType.serviceUnavailable);
  }

  /// Closes the underlying [AncApiClient], but only when this instance
  /// created it (via [AuthService.production]); a caller-supplied client is
  /// left open for the caller to manage. Safe to call more than once.
  void close() {
    if (_ownsApiClient) _apiClient.close();
  }
}
