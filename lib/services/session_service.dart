import 'auth_session_store.dart';
import 'secure_auth_session_store.dart';

/// Purpose: Owns the authenticated-session lifecycle for the whole app:
/// whether one is active, and clearing one on logout. This is the app's
/// single seam for session state — screens must go through it rather than
/// reading/writing storage (secure or otherwise) directly.
///
/// Responsibilities:
/// - Report whether a secure authenticated session currently exists.
/// - Clear that session on logout.
///
/// Must not:
/// - Treat the legacy `session_is_logged_in` SharedPreferences Boolean as
///   authentication — the secure `AuthSession` (see [AuthSessionStore]) is
///   the only source of truth.
/// - Perform navigation, show UI, or hold a `BuildContext`.
/// - Make an HTTP request — login itself goes through `AuthService`, not
///   this seam.
abstract interface class SessionService {
  /// Whether an authenticated session is currently active, as read from
  /// the secure `AuthSession` only. Used by the app-startup gate (see
  /// `main.dart`) so a relaunch after logout opens on Login rather than an
  /// authenticated screen, without relying on in-memory state or the
  /// legacy Boolean.
  Future<bool> isLoggedIn();

  /// Clears the authenticated session. Called on logout.
  ///
  /// Throws on failure (see [SecureSessionService]) rather than returning
  /// a result object — callers must treat a thrown error as a failed
  /// sign-out, never as success.
  Future<void> endSession();
}

/// Default [SessionService]: a thin façade over the secure
/// [AuthSessionStore], so screens depend on this narrow session-lifecycle
/// seam instead of the storage layer directly.
class SecureSessionService implements SessionService {
  SecureSessionService({AuthSessionStore? sessionStore})
    : _sessionStore = sessionStore ?? SecureAuthSessionStore();

  final AuthSessionStore _sessionStore;

  @override
  Future<bool> isLoggedIn() => _sessionStore.hasValidSession();

  @override
  // TODO(api): Call the official ANC API logout/revocation endpoint before
  // local session deletion once its endpoint contract is provided.
  Future<void> endSession() => _sessionStore.clear();
}
