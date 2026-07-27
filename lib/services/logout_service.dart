/// Purpose: The narrow seam for explicit, user-initiated logout — attempting
/// best-effort remote revocation and then unconditionally clearing the
/// local secure session. See `AuthService.logout` (the sole production
/// implementation) for the full per-outcome contract.
///
/// Responsibilities:
/// - Provide exactly one operation: [logout].
///
/// Must not:
/// - Be used for passive session expiry — a protected request returning
///   HTTP 401 while already inside the app goes through
///   `SessionExpiryCoordinator`/`SessionService` instead, which never
///   attempts remote revocation against a token already known to be
///   invalid. This seam exists specifically to keep that path separate from
///   explicit, user-initiated logout.
/// - Perform navigation, show UI, or hold a `BuildContext`.
abstract interface class LogoutService {
  /// Attempts remote revocation (best-effort: a remote failure is not
  /// escalated) and then unconditionally clears the local secure session.
  ///
  /// Throws `SessionStorageException` only when the local secure-session
  /// clear itself fails — never for a remote-only failure.
  Future<void> logout();
}
