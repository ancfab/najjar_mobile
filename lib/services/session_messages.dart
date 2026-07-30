/// Purpose: The one shared source of truth for *which* safe, neutral
/// message to show after a session is invalidated or its state couldn't be
/// determined — whether that happens during app-startup validation
/// (`main.dart`'s `resolveStartupSession`) or during a runtime request made
/// while already inside the app (`SessionExpiryCoordinator`).
///
/// Deliberately a reason, not a formatted string: the actual localized text
/// is resolved by [LoginScreen] at display time (via `context.t`), since
/// `main.dart` and `SessionExpiryCoordinator` run before/outside a
/// `Localizations`-wrapped widget tree and can't format user-facing text
/// themselves.
enum LoginStartupMessage {
  /// A previously active session was confirmed revoked/unusable.
  sessionExpired,

  /// A stored session's validity could not be confirmed (e.g. no network).
  validationUnavailable,

  /// The locally persisted secure session could not be read at all.
  restoreFailed,
}
