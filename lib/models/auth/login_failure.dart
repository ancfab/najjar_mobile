import 'auth_session.dart';

/// Purpose: The typed result [AuthService.login] returns, so the future
/// LoginScreen can distinguish success from failure — and distinguish kinds
/// of failure — without inspecting HTTP status codes, exception types, or
/// raw response bodies.
///
/// Responsibilities:
/// - [AuthLoginSuccess] carries the persisted [AuthSession] on success.
/// - [AuthLoginFailure] carries a small, stable [AuthLoginFailureType] plus,
///   for [AuthLoginFailureType.invalidPhone] only, a safe single message
///   string suitable for inline display.
///
/// Must not:
/// - Carry a raw HTTP status code, [Exception], response body, or any
///   backend message not already vetted as safe to surface (see
///   [AuthLoginFailure.phoneError]).
/// - Carry a password or token in any field or in [toString].
sealed class AuthLoginResult {
  const AuthLoginResult();
}

/// A successful login: the API call succeeded and [session] has already
/// been persisted through `AuthSessionStore` before this is returned.
class AuthLoginSuccess extends AuthLoginResult {
  const AuthLoginSuccess(this.session);

  final AuthSession session;

  /// Deliberately omits the session's token (see [AuthSession.toString]).
  @override
  String toString() => 'AuthLoginSuccess(userId: ${session.userId})';
}

/// The small, stable set of ways a login attempt can fail, safe for the
/// future LoginScreen to switch on directly.
enum AuthLoginFailureType {
  /// A required value was empty before any API call was made.
  invalidInput,

  /// A neutral credential failure: wrong password, unknown username/phone,
  /// a deactivated account, or a backend account misconfiguration. The ANC
  /// API deliberately does not distinguish these (see the HTTP 422 mapping
  /// in `AuthService`), so this must never be presented as "wrong
  /// password" or "unknown username" specifically.
  invalidCredentials,

  /// HTTP 422 with a validation error under `errors.phone`.
  invalidPhone,

  /// The request never reached the server, or no response was received
  /// (including a timeout).
  network,

  /// The ANC API reached but failed to service the request (HTTP 5xx, or
  /// another unexpected non-success status — see `AuthService`'s
  /// documented deterministic mapping).
  serviceUnavailable,

  /// A response was received but its body did not match the expected
  /// shape.
  invalidResponse,

  /// The HTTP login succeeded but persisting the resulting session to
  /// secure storage failed. Not a successful application login.
  secureStorage,
}

/// A failed login attempt. See [AuthLoginFailureType] for what each value
/// means and what it must not imply.
class AuthLoginFailure extends AuthLoginResult {
  const AuthLoginFailure(this.type, {this.phoneError});

  final AuthLoginFailureType type;

  /// The first safe message from the backend's `errors.phone`, present
  /// only when [type] is [AuthLoginFailureType.invalidPhone]. Never the
  /// complete raw validation response.
  final String? phoneError;

  @override
  String toString() => 'AuthLoginFailure(type: $type)';
}
