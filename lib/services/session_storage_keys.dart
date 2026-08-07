/// Purpose: Single source of truth for the SharedPreferences key names this
/// app writes for session-adjacent local state.
///
/// Responsibilities:
/// - Keep the legacy pre-authentication login-flag key defined in exactly
///   one place, so `SecureAuthSessionStore` can never duplicate or diverge
///   on the literal string.
///
/// Must not:
/// - Be treated as an authentication source — [isLoggedIn] is a retired
///   legacy flag; the secure `AuthSession` (see `SessionService`) is the
///   only source of truth for whether a user is signed in.
class SessionStorageKeys {
  SessionStorageKeys._();

  /// Legacy pre-authentication mock login flag. No longer authoritative —
  /// see `SessionService`/`SecureSessionService` — retained only so
  /// `SecureAuthSessionStore.clear()` can remove it from a device that
  /// still has it set from before the secure-session migration.
  static const String isLoggedIn = 'session_is_logged_in';

  /// The user's selected app language code (e.g. `'en'`, `'ar'`, `'fr'`) —
  /// see `LocaleController`. Not sensitive, so plain SharedPreferences (not
  /// secure storage) is the appropriate store.
  static const String localeCode = 'session_locale_code';
}
