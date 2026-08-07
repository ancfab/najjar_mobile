import 'auth_session.dart';

/// Purpose: The typed result [AuthService.updateProfile] returns, so a
/// future profile screen can distinguish success from failure — and
/// distinguish kinds of failure — without inspecting HTTP status codes,
/// exception types, or raw response bodies. Mirrors [AuthLoginResult]'s
/// shape.
///
/// Responsibilities:
/// - [UpdateProfileSuccess] carries the re-persisted [AuthSession] with
///   refreshed identity fields on success.
/// - [UpdateProfileFailure] carries a small, stable [UpdateProfileFailureType]
///   plus, for [UpdateProfileFailureType.usernameTaken] and
///   [UpdateProfileFailureType.invalidPhone] only, a safe single message
///   string suitable for inline display.
///
/// Must not:
/// - Carry a raw HTTP status code, [Exception], response body, or any
///   backend message not already vetted as safe to surface.
/// - Carry a token in any field or in [toString].
sealed class UpdateProfileResult {
  const UpdateProfileResult();
}

/// A successful profile update: the API call succeeded and the refreshed
/// [session] has already been persisted through `AuthSessionStore` before
/// this is returned.
class UpdateProfileSuccess extends UpdateProfileResult {
  const UpdateProfileSuccess(this.session);

  final AuthSession session;

  @override
  String toString() => 'UpdateProfileSuccess(userId: ${session.userId})';
}

/// The small, stable set of ways a profile-update attempt can fail, safe
/// for a future screen to switch on directly.
enum UpdateProfileFailureType {
  /// Neither `username` nor `phone` was supplied, or both were empty after
  /// trimming — checked locally before any API call is made.
  invalidInput,

  /// HTTP 422 with a validation error under `errors.username` — per the
  /// contract, username uniqueness is scoped to the user's own `client_id`
  /// and country.
  usernameTaken,

  /// HTTP 422 with a validation error under `errors.phone` — including
  /// normalization or global-uniqueness failures.
  invalidPhone,

  /// No session is currently stored, or the ANC API rejected the stored
  /// token with HTTP 401 (the local session is cleared in that case, same
  /// as `AuthService.confirmSession`).
  unauthorized,

  /// The request never reached the server, or no response was received
  /// (including a timeout).
  network,

  /// The ANC API reached but failed to service the request (HTTP 5xx, or
  /// another unexpected non-success status not covered above).
  serviceUnavailable,

  /// A response was received but its body did not match the expected
  /// shape.
  invalidResponse,

  /// The HTTP update succeeded but persisting the refreshed session to
  /// secure storage failed, or the stored session could not be read.
  secureStorage,
}

/// A failed profile-update attempt. See [UpdateProfileFailureType] for what
/// each value means and what it must not imply.
class UpdateProfileFailure extends UpdateProfileResult {
  const UpdateProfileFailure(this.type, {this.usernameError, this.phoneError});

  final UpdateProfileFailureType type;

  /// The first safe message from the backend's `errors.username`, present
  /// only when [type] is [UpdateProfileFailureType.usernameTaken].
  final String? usernameError;

  /// The first safe message from the backend's `errors.phone`, present
  /// only when [type] is [UpdateProfileFailureType.invalidPhone].
  final String? phoneError;

  @override
  String toString() => 'UpdateProfileFailure(type: $type)';
}
