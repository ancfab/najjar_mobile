import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/current_user_avatar_controller.dart';
import 'services/session_service.dart';
import 'services/session_storage_exception.dart';
import 'theme/app_colors.dart';

/// Safe, one-time message shown on Login after a startup secure-session
/// restore failure (see [resolveStartupSession]) — never a storage
/// implementation detail.
const String _secureSessionRestoreFailedMessage =
    'We could not restore your secure session. Please sign in again.';

/// App-startup auth-gate result: whether a previously-established secure
/// session is still active, and an optional safe message to show once on
/// Login when that could not be determined.
typedef StartupSession = ({bool isLoggedIn, String? startupMessage});

/// Resolves the app-startup authentication state from [sessionService]
/// alone — the secure `AuthSession` is the only source of truth (see
/// [SessionService.isLoggedIn]); the legacy Boolean is never consulted. A
/// genuine secure-storage read failure routes to Login with
/// [_secureSessionRestoreFailedMessage] rather than crashing before
/// `runApp` or falling back to any legacy signal. Makes no network call
/// and never decodes or otherwise inspects token contents.
Future<StartupSession> resolveStartupSession(
  SessionService sessionService,
) async {
  try {
    final isLoggedIn = await sessionService.isLoggedIn();
    return (isLoggedIn: isLoggedIn, startupMessage: null);
  } on SessionStorageException {
    return (
      isLoggedIn: false,
      startupMessage: _secureSessionRestoreFailedMessage,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Startup auth gate: reads the persisted secure session (not just
  // in-memory state) before the first frame, so a relaunch after logout
  // opens on Login rather than briefly showing — or worse, staying on — an
  // authenticated screen.
  final startup = await resolveStartupSession(SecureSessionService());
  if (startup.isLoggedIn) {
    // Restores the temporary local/mock avatar (see
    // CurrentUserAvatarController) so it's already in place on the first
    // authenticated frame instead of popping in after a rebuild.
    await currentUserAvatarController.restorePersisted();
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
  const MyApp({super.key, this.isLoggedIn = false, this.startupMessage});

  /// Whether a previously-established session is still active, as
  /// determined by [resolveStartupSession] before the widget tree is
  /// built. Defaults to false (Login) so widget tests that construct
  /// MyApp() directly — bypassing main()'s async startup check — see the
  /// same behavior as a fresh, logged-out install.
  final bool isLoggedIn;

  /// A safe, one-time message to show on Login after a startup secure-
  /// session restore failure, or null when nothing needs to be shown.
  final String? startupMessage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ANC Fabrics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryNavy,
          surface: AppColors.background,
        ),
      ),
      home: isLoggedIn
          ? const HomeScreen()
          : LoginScreen(startupMessage: startupMessage),
    );
  }
}
