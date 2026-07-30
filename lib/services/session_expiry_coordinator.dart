import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import 'current_user_avatar_controller.dart';
import 'session_messages.dart';
import 'session_service.dart';

/// The app's root [Navigator] key, so [SessionExpiryCoordinator] can replace
/// the entire back stack with Login from outside the widget tree (no
/// authenticated screen keeps a `BuildContext` reachable after that). Shared
/// with `MyApp`'s [MaterialApp] — see `main.dart`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Purpose: The single centralized handler for "this authenticated request
/// just got HTTP 401 while the user was already inside the app" — the
/// runtime counterpart to `main.dart`'s cold-start `resolveStartupSession`
/// gate, which only covers the moment the app launches.
///
/// Responsibilities:
/// - Clear the secure session via the existing [SessionService] seam (never
///   touching secure storage directly).
/// - Clear in-memory authenticated-user state via the existing
///   [CurrentUserAvatarController] seam.
/// - Replace the entire navigation stack with [LoginScreen] so no
///   previously-pushed authenticated screen remains reachable.
/// - Collapse concurrent callers (e.g. two requests racing to a 401 at
///   nearly the same time) into exactly one invalidation/navigation.
///
/// Must not:
/// - Be called for anything other than a confirmed HTTP 401 — 422/502/503/
///   network failures must never reach this.
/// - Show an endpoint error toast or error card; the whole point of routing
///   through here is that Login appears instead, with no error state left
///   behind on the screen the user was just on.
class SessionExpiryCoordinator {
  SessionExpiryCoordinator({
    SessionService? sessionService,
    CurrentUserAvatarController? avatarController,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : _sessionService = sessionService ?? SecureSessionService(),
       _avatarController = avatarController ?? currentUserAvatarController,
       _navigatorKey = navigatorKey ?? appNavigatorKey;

  final SessionService _sessionService;
  final CurrentUserAvatarController _avatarController;
  final GlobalKey<NavigatorState> _navigatorKey;

  /// Guards against a second, concurrent 401 re-running invalidation/
  /// navigation. Set synchronously before the first `await` in
  /// [handleUnauthorized], so two near-simultaneous callers can never both
  /// pass the check — Dart never interleaves execution between awaits.
  bool _invalidating = false;

  /// Handles a confirmed HTTP 401: clears the session and in-memory user
  /// state, then replaces the entire navigation stack with [LoginScreen].
  /// Safe to call more than once — every call after the first is a no-op.
  Future<void> handleUnauthorized() async {
    if (_invalidating) return;
    _invalidating = true;

    try {
      await _sessionService.endSession();
    } catch (_) {
      // Best-effort: the token is already confirmed dead server-side, so a
      // local clear failure must not block navigating away from Home.
    }
    await _avatarController.clear();

    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(
          startupMessage: LoginStartupMessage.sessionExpired,
        ),
      ),
      (route) => false,
    );
  }

  /// Test-only hook to re-arm the guard after a fresh login, so a test can
  /// exercise [handleUnauthorized] more than once against the same
  /// instance. Never called from production code.
  @visibleForTesting
  void resetForTesting() {
    _invalidating = false;
  }
}

/// App-wide singleton, matching [currentUserAvatarController]'s convention.
/// Services default to this instance; constructor parameters still accept
/// an explicit override so tests can inject a fresh instance.
final SessionExpiryCoordinator sessionExpiryCoordinator =
    SessionExpiryCoordinator();
