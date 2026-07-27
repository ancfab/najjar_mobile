/// Purpose: The one shared source of truth for user-facing copy shown after
/// a session is invalidated, whether that happens during app-startup
/// validation (`main.dart`'s `resolveStartupSession`) or during a runtime
/// request made while already inside the app (`SessionExpiryCoordinator`) —
/// both cases must show identical wording.
const String sessionExpiredMessage =
    'Your session has expired. Please sign in again.';
