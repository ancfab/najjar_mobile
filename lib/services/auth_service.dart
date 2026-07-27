import '../config/api_config.dart';
import '../models/auth/auth_session.dart';
import '../models/auth/login_failure.dart';
import '../models/auth/login_request.dart';
import '../models/auth/login_response.dart';
import '../models/auth/session_validation_result.dart';
import 'anc_api_client.dart';
import 'anc_api_exceptions.dart';
import 'auth_session_store.dart';
import 'logout_service.dart';
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
/// - Call `GET /auth/me` through [AncApiClient.fetchCurrentUser] to
///   re-validate a persisted session on cold app launch (see
///   [confirmSession]), never trusting a locally stored token alone.
///
/// - Implement explicit, user-initiated logout (see [logout] and
///   [LogoutService]): a best-effort `POST /auth/logout` call followed by an
///   unconditional local secure-session clear. Deliberately separate from
///   passive session expiry (`SessionExpiryCoordinator`/`SessionService`),
///   which must never attempt remote revocation against a token already
///   confirmed invalid.
///
/// Must not:
/// - Contain navigation or widget logic.
/// - Store or log passwords, tokens, or raw API responses.
/// - Communicate directly with Business Central.
/// - Implement token refresh or a timer-based expiry — none exists.
/// - Clear in-memory authenticated-user state (e.g. the avatar) or show UI —
///   [logout]'s caller owns both, the same way `EditProfileScreen` already
///   does for the local-only flow it replaces.
class AuthService implements LogoutService {
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

  /// Re-validates a persisted secure session against `GET /auth/me`, per
  /// the app-startup contract in `main.dart`: a locally stored token is
  /// never trusted on its own.
  ///
  /// - No stored session -> [SessionValidationAbsent].
  /// - The stored session cannot even be read (a secure-storage I/O
  ///   failure) -> [SessionValidationStorageFailure]; the session is left
  ///   untouched since nothing is known to safely clear.
  /// - HTTP 200 -> the session is re-persisted with identity fields
  ///   refreshed from the response (see [AuthSession.fromAuthenticatedUser])
  ///   and [SessionValidationValid] is returned. A failure to re-persist is
  ///   not escalated — the freshly confirmed data is still safe to use for
  ///   this launch even if it could not be written back.
  /// - HTTP 401 -> the token is revoked; the secure session is cleared
  ///   (best-effort — see [_clearIgnoringStorageFailure]) and
  ///   [SessionValidationRevoked] is returned.
  /// - A malformed response body -> the secure session is cleared, since it
  ///   cannot be trusted, and [SessionValidationUnusable] is returned.
  /// - A network failure, timeout, or any other unexpected HTTP status ->
  ///   the secure session is left untouched and
  ///   [SessionValidationUnavailable] is returned; this must never be
  ///   treated as an invalid credential.
  Future<SessionValidationResult> confirmSession() async {
    final AuthSession? stored;
    try {
      stored = await _sessionStore.read();
    } on SessionStorageException {
      return const SessionValidationStorageFailure();
    }
    if (stored == null) return const SessionValidationAbsent();

    try {
      final user = await _apiClient.fetchCurrentUser(token: stored.token);
      final updated = AuthSession.fromAuthenticatedUser(
        token: stored.token,
        user: user,
      );
      try {
        await _sessionStore.save(updated);
      } on SessionStorageException {
        // Best-effort refresh only; see doc comment above.
      }
      return SessionValidationValid(updated);
    } on AncHttpException catch (error) {
      if (error.statusCode == 401) {
        await _clearIgnoringStorageFailure();
        return const SessionValidationRevoked();
      }
      return const SessionValidationUnavailable();
    } on AncNetworkException {
      return const SessionValidationUnavailable();
    } on AncProtocolException {
      await _clearIgnoringStorageFailure();
      return const SessionValidationUnusable();
    }
  }

  /// Clears the secure session, swallowing a [SessionStorageException] so a
  /// failure to also delete the local copy never blocks reporting that the
  /// token is confirmed dead/unusable server-side — correctness of that
  /// outcome (never showing Home with it) matters more than surfacing a
  /// storage error mid-validation.
  Future<void> _clearIgnoringStorageFailure() async {
    try {
      await _sessionStore.clear();
    } on SessionStorageException {
      // Intentionally ignored; see doc comment above.
    }
  }

  /// Explicit, user-initiated logout: attempts `POST /auth/logout` on a
  /// best-effort basis, then unconditionally clears the local secure
  /// session — implementing [LogoutService] for callers such as
  /// `EditProfileScreen`.
  ///
  /// Sequence:
  /// 1. Read the stored [AuthSession]. A [SessionStorageException] here
  ///    (the session itself cannot be read) is treated as "no token
  ///    available" for the remote step below — this never creates an
  ///    in-memory token cache, and local clear is still attempted next.
  /// 2. If a token is available, attempt [AncApiClient.logout]. Every
  ///    [AncApiException] outcome — HTTP 401/422/5xx, a timeout, a network
  ///    failure, or a malformed response — is swallowed here: the remote
  ///    result never gates, delays, or blocks the local clear that follows,
  ///    and is never retried.
  /// 3. Unconditionally call [AuthSessionStore.clear]. This is the only
  ///    step whose failure this method surfaces: a thrown
  ///    [SessionStorageException] propagates unchanged (the secure token is
  ///    guaranteed still present per [SecureAuthSessionStore.clear]'s
  ///    ordering guarantee), so the caller must not navigate to Login or
  ///    treat this call as a successful sign-out.
  ///
  /// Never clears in-memory authenticated-user state, shows UI, or
  /// navigates — the caller (see `EditProfileScreen._handleLogout`) owns
  /// all three, exactly as it already does for the local-only flow this
  /// replaces.
  @override
  Future<void> logout() async {
    AuthSession? stored;
    try {
      stored = await _sessionStore.read();
    } on SessionStorageException {
      stored = null;
    }

    final token = stored?.token;
    if (token != null) {
      try {
        await _apiClient.logout(token: token);
      } on AncApiException {
        // Best-effort remote revocation only; see the method doc comment
        // above — no remote outcome may prevent the local clear below.
      }
    }

    await _sessionStore.clear();
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
