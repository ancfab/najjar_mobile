import '../models/auth/auth_session.dart';

/// Purpose: The app's single seam for persisting and retrieving the
/// authenticated ANC API session, independent of which storage mechanism
/// backs it.
///
/// Responsibilities:
/// - Save a complete authenticated session, overwriting any prior one.
/// - Read the current session, or `null` when none exists or the
///   persisted data is missing/invalid.
/// - Report whether a valid secure session currently exists.
/// - Clear the persisted session completely.
///
/// Must not:
/// - Perform navigation, show UI, or hold a `BuildContext`.
/// - Make HTTP requests, refresh tokens, or handle HTTP 401 responses.
/// - Talk to Business Central.
///
/// Not yet wired to `LoginScreen`, `main.dart`, or logout — see Phase 2's
/// scope note in the implementations of this interface.
abstract interface class AuthSessionStore {
  Future<void> save(AuthSession session);

  Future<AuthSession?> read();

  Future<bool> hasValidSession();

  Future<void> clear();
}
