/// Purpose: The typed result [AuthService.changePassword] returns, so a
/// future change-password screen can distinguish success from failure —
/// and distinguish kinds of failure — without inspecting HTTP status codes,
/// exception types, or raw response bodies. Mirrors [AuthLoginResult]'s
/// shape.
///
/// Responsibilities:
/// - [ChangePasswordSuccess] marks that `PUT /api/auth/me/password`
///   returned HTTP 200. Per the confirmed contract this endpoint does not
///   rotate or revoke the current bearer token, so there is no session to
///   carry.
/// - [ChangePasswordFailure] carries a small, stable
///   [ChangePasswordFailureType] plus, for
///   [ChangePasswordFailureType.weakPassword] and
///   [ChangePasswordFailureType.passwordConfirmationMismatch], a safe
///   single message string suitable for inline display.
///
/// Must not:
/// - Carry a raw HTTP status code, [Exception], response body, or any
///   backend message not already vetted as safe to surface.
/// - Carry a password or token in any field or in [toString].
sealed class ChangePasswordResult {
  const ChangePasswordResult();
}

/// A successful password change.
class ChangePasswordSuccess extends ChangePasswordResult {
  const ChangePasswordSuccess();

  @override
  String toString() => 'ChangePasswordSuccess()';
}

/// The small, stable set of ways a password-change attempt can fail, safe
/// for a future screen to switch on directly.
enum ChangePasswordFailureType {
  /// `currentPassword`, `password`, or `passwordConfirmation` was empty —
  /// checked locally before any API call is made.
  invalidInput,

  /// HTTP 422 with a validation error under `errors.current_password` —
  /// the supplied current password did not match.
  incorrectCurrentPassword,

  /// HTTP 422 with a validation error under `errors.password` — the new
  /// password failed the contract's length/mixed-case/number/symbol rules.
  weakPassword,

  /// HTTP 422 with a validation error under `errors.password_confirmation`
  /// (and no `errors.password`) — the confirmation did not match the new
  /// password.
  passwordConfirmationMismatch,

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

  /// The stored session could not be read from secure storage.
  secureStorage,
}

/// A failed password-change attempt. See [ChangePasswordFailureType] for
/// what each value means and what it must not imply.
class ChangePasswordFailure extends ChangePasswordResult {
  const ChangePasswordFailure(this.type, {this.passwordError});

  final ChangePasswordFailureType type;

  /// The first safe message from the backend's `errors.password` or
  /// `errors.password_confirmation`, present only when [type] is
  /// [ChangePasswordFailureType.weakPassword] or
  /// [ChangePasswordFailureType.passwordConfirmationMismatch].
  final String? passwordError;

  @override
  String toString() => 'ChangePasswordFailure(type: $type)';
}
