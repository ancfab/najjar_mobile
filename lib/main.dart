import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'localization/app_locale.dart';
import 'localization/app_translations_delegate.dart';
import 'models/auth/session_validation_result.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/current_user_avatar_controller.dart';
import 'services/locale_controller.dart';
import 'services/session_expiry_coordinator.dart';
import 'services/session_messages.dart';
import 'theme/app_colors.dart';
import 'theme/app_typography.dart';

/// App-startup auth-gate result: whether a previously-established secure
/// session is both present and confirmed still valid, an optional safe
/// message reason to show once on Login when that could not be determined
/// (resolved to localized text by [LoginScreen] itself, since this runs
/// before any `Localizations`-wrapped widget tree exists), and whether the
/// session was actively invalidated during this check (as opposed to simply
/// never having existed) — see [resolveStartupSession].
typedef StartupSession = ({
  bool isLoggedIn,
  LoginStartupMessage? startupMessage,
  bool sessionInvalidated,
});

/// Resolves the app-startup authentication state via
/// [AuthService.confirmSession] — a locally stored token is never trusted
/// on its own; a returning user's session is only treated as active once
/// `GET /auth/me` confirms it. Makes at most one network call and never
/// decodes or otherwise inspects token contents.
Future<StartupSession> resolveStartupSession(AuthService authService) async {
  final result = await authService.confirmSession();
  return switch (result) {
    SessionValidationAbsent() => (
      isLoggedIn: false,
      startupMessage: null,
      sessionInvalidated: false,
    ),
    SessionValidationValid() => (
      isLoggedIn: true,
      startupMessage: null,
      sessionInvalidated: false,
    ),
    SessionValidationRevoked() => (
      isLoggedIn: false,
      startupMessage: LoginStartupMessage.sessionExpired,
      sessionInvalidated: true,
    ),
    SessionValidationUnusable() => (
      isLoggedIn: false,
      startupMessage: LoginStartupMessage.sessionExpired,
      sessionInvalidated: true,
    ),
    SessionValidationUnavailable() => (
      isLoggedIn: false,
      startupMessage: LoginStartupMessage.validationUnavailable,
      sessionInvalidated: false,
    ),
    SessionValidationStorageFailure() => (
      isLoggedIn: false,
      startupMessage: LoginStartupMessage.restoreFailed,
      sessionInvalidated: false,
    ),
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Startup auth gate: confirms any persisted secure session against
  // `GET /auth/me` (not just its local presence) before the first frame, so
  // a relaunch never briefly shows — or worse, stays on — an authenticated
  // screen for a token the backend has since revoked.
  final authService = AuthService.production();
  final startup = await resolveStartupSession(authService);
  authService.close();

  // Restores the user's previously selected language (if any) before the
  // first frame, so the app never flashes the fallback language then
  // switches.
  await localeController.restorePersisted();

  if (startup.isLoggedIn) {
    // Restores the temporary local/mock avatar (see
    // CurrentUserAvatarController) so it's already in place on the first
    // authenticated frame instead of popping in after a rebuild.
    await currentUserAvatarController.restorePersisted();
  } else if (startup.sessionInvalidated) {
    // The centralized invalid-session path: a session that was confirmed
    // revoked/unusable during this check must not leave stale in-memory
    // authenticated-user state (here, a locally cached avatar) around for
    // whichever account signs in next on this device.
    await currentUserAvatarController.clear();
  }

  runApp(
    MyApp(
      isLoggedIn: startup.isLoggedIn,
      startupMessage: startup.startupMessage,
    ),
  );
}

/// Purpose: The app's root widget and startup routing gate.
///
/// Responsibilities:
/// - Show Home when [isLoggedIn] is true — as resolved by
///   [resolveStartupSession] before `runApp` — otherwise Login.
/// - Forward [startupMessage] to Login so a startup secure-session restore
///   failure can be surfaced once, safely.
///
/// Must not:
/// - Re-check the session itself — `main()` already resolves [isLoggedIn]
///   before constructing this widget, so widget tests can supply either
///   value directly without touching secure storage or any platform
///   channel.
class MyApp extends StatelessWidget {
  MyApp({
    super.key,
    this.isLoggedIn = false,
    this.startupMessage,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : navigatorKey = navigatorKey ?? appNavigatorKey;

  /// Whether a previously-established session is still active, as
  /// determined by [resolveStartupSession] before the widget tree is
  /// built. Defaults to false (Login) so widget tests that construct
  /// MyApp() directly — bypassing main()'s async startup check — see the
  /// same behavior as a fresh, logged-out install.
  final bool isLoggedIn;

  /// A safe, one-time message reason to show on Login after a startup
  /// secure-session restore failure, or null when nothing needs to be
  /// shown.
  final LoginStartupMessage? startupMessage;

  /// The app's root [Navigator] key. Defaults to the shared
  /// [appNavigatorKey] that [SessionExpiryCoordinator] uses to replace the
  /// whole back stack with Login after a runtime 401 — overridable so
  /// widget tests can supply a fresh key per test instead of reusing the
  /// app-wide singleton across independently torn-down widget trees.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'ANC Fabrics',
          debugShowCheckedModeBanner: false,
          locale: localeController.locale,
          supportedLocales: AppLocale.supportedLocales,
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: AppColors.background,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primaryNavy,
              surface: AppColors.background,
              error: AppColors.dangerRed,
            ),
            // Mirrors the shared AppTypography scale onto Material's
            // ambient TextTheme slots so any future widget that reads
            // Theme.of(context).textTheme gets the same scale existing
            // screens already use via AppTypography directly. No current
            // widget reads textTheme, so this is purely additive and does
            // not change any existing screen's appearance.
            textTheme: const TextTheme(
              displayLarge: AppTypography.displayValue,
              titleLarge: AppTypography.pageTitle,
              titleMedium: AppTypography.sectionTitle,
              titleSmall: AppTypography.cardTitle,
              bodyMedium: AppTypography.body,
              bodySmall: AppTypography.bodySecondary,
              labelLarge: AppTypography.buttonText,
              labelMedium: AppTypography.label,
              labelSmall: AppTypography.caption,
            ),
          ),
          home: isLoggedIn
              ? const HomeScreen()
              : LoginScreen(startupMessage: startupMessage),
        );
      },
    );
  }
}
