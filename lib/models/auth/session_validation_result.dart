import 'auth_session.dart';

/// Purpose: The typed result `AuthService.confirmSession` returns when
/// re-validating a persisted secure session against `GET /auth/me` on cold
/// app launch (see `main.dart`'s startup gate) — a locally stored token is
/// never trusted on its own.
///
/// Responsibilities:
/// - Distinguish "no session to validate" from a confirmed-valid session,
///   a confirmed-revoked session (HTTP 401), an unusable response the
///   backend cannot be trusted to have answered, and a validation attempt
///   that could not be completed at all (storage or network failure) —
///   because only the first two are safe to route to Login/Home directly,
///   while the last must never be mistaken for invalid credentials.
///
/// Must not:
/// - Carry a raw HTTP status code, [Exception], or response body.
/// - Carry a password or token in any field.
sealed class SessionValidationResult {
  const SessionValidationResult();
}

/// No secure session exists on this device — a normal fresh/logged-out
/// state, not a failure.
class SessionValidationAbsent extends SessionValidationResult {
  const SessionValidationAbsent();
}

/// The stored session was confirmed by the ANC API. [session] carries the
/// identity fields refreshed from `/auth/me`'s response (same token,
/// updated user fields) and has already been re-persisted.
class SessionValidationValid extends SessionValidationResult {
  const SessionValidationValid(this.session);

  final AuthSession session;
}

/// The ANC API returned HTTP 401 for the stored token: it is revoked/dead.
/// The secure session has already been cleared.
class SessionValidationRevoked extends SessionValidationResult {
  const SessionValidationRevoked();
}

/// The `/auth/me` response could not be parsed (missing the `data` wrapper,
/// or a malformed user object). Treated as unusable rather than trusted —
/// the secure session has already been cleared.
class SessionValidationUnusable extends SessionValidationResult {
  const SessionValidationUnusable();
}

/// `/auth/me` could not be reached, timed out, or the ANC API failed to
/// service the request (an unexpected non-2xx/non-401 status). This is not
/// evidence the token is invalid — the secure session is left untouched.
class SessionValidationUnavailable extends SessionValidationResult {
  const SessionValidationUnavailable();
}

/// The locally persisted session could not even be read (a secure-storage
/// I/O failure) — kept distinct from [SessionValidationUnavailable] so a
/// device/platform storage failure is never conflated with a network
/// failure. The secure session is left untouched (there is nothing known
/// to safely clear).
class SessionValidationStorageFailure extends SessionValidationResult {
  const SessionValidationStorageFailure();
}
