import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted-storage keys for authenticated-session data, centralized so
/// every key this app ever writes for a session is also known to
/// [SharedPreferencesSessionService.endSession] and can't be missed or
/// cleared piecemeal. Logout removes exactly these keys (not a global
/// SharedPreferences.clear()), so device-level settings such as theme,
/// language, or onboarding choice — which aren't session data — are never
/// touched by logout.
///
/// TODO(api): Add real keys here (accessToken, refreshToken, tenantId,
/// companyId, cached current-user profile, ...) once an authentication
/// backend defines what an authenticated session actually contains. Today
/// only a login flag and the temporary local/mock avatar path are
/// persisted, since no real credentials or backend avatar URL exist yet —
/// see [SharedPreferencesSessionService] and `CurrentUserAvatarController`.
class SessionStorageKeys {
  SessionStorageKeys._();

  static const String isLoggedIn = 'session_is_logged_in';

  /// Path to the locally persisted mock avatar file (see
  /// `CurrentUserAvatarController`). User-specific, so it's cleared on
  /// logout the same as every other session key — otherwise the next
  /// signed-in user on this device would see the previous user's avatar.
  static const String localAvatarPath = 'session_local_avatar_path';

  /// Every key written for an authenticated session.
  static const List<String> all = [isLoggedIn, localAvatarPath];
}

/// How a [SessionService.endSession] attempt resolved.
enum SessionEndOutcome {
  /// The local session was cleared; it is safe to route to Login.
  success,

  /// The local session could not be cleared reliably. The caller must keep
  /// the user on the current authenticated screen rather than risk a
  /// partially authenticated state.
  failure,
}

class SessionEndResult {
  const SessionEndResult(this.outcome, {this.message});

  final SessionEndOutcome outcome;

  /// Optional user-safe message describing the outcome — never a stack
  /// trace or other implementation detail.
  final String? message;

  bool get succeeded => outcome == SessionEndOutcome.success;

  static const SessionEndResult success = SessionEndResult(
    SessionEndOutcome.success,
  );
}

/// Owns the authenticated-session lifecycle for the whole app: whether one
/// is active, starting one after a successful login, and clearing one on
/// logout. This is the app's single seam for session state — screens must
/// go through it rather than reading/writing storage directly.
abstract class SessionService {
  /// Whether an authenticated session is currently active, as read from
  /// persisted storage. Used by the app-startup gate (see `main.dart`) so a
  /// relaunch after logout opens on Login rather than an authenticated
  /// screen, without relying on in-memory state alone.
  Future<bool> isLoggedIn();

  /// Marks an authenticated session as active. Called after a successful
  /// login.
  Future<void> startSession();

  /// Clears the authenticated session. Called on logout; always attempts
  /// the local clear even if an optional remote revocation call fails, so
  /// the device never keeps working credentials the user asked to sign out
  /// of.
  Future<SessionEndResult> endSession();
}

/// Default [SessionService]: persists session state with SharedPreferences,
/// this project's only local-storage mechanism (no secure storage, Hive, or
/// similar is used anywhere else in the app).
///
/// TODO(api): No logout/token-revocation endpoint exists in this project
/// yet — there is no API base URL, request/response contract, or auth
/// backend documented or implemented anywhere (same gap as
/// UnavailableProfileService for profile updates). [endSession] therefore
/// only clears the local session; it does not call a server. Once a real
/// auth backend exists, add the remote revocation call here (e.g. POST
/// /auth/logout with the current refresh token, read before it's removed
/// below) and make sure a failure from that optional call still does not
/// block the local clear — only the local-clear failure path below should.
class SharedPreferencesSessionService implements SessionService {
  const SharedPreferencesSessionService();

  @override
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SessionStorageKeys.isLoggedIn) ?? false;
  }

  @override
  Future<void> startSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SessionStorageKeys.isLoggedIn, true);
  }

  @override
  Future<SessionEndResult> endSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in SessionStorageKeys.all) {
        await prefs.remove(key);
      }
      return SessionEndResult.success;
    } catch (error) {
      // Technical detail only — never shown to the user.
      debugPrint('Session cleanup failed: $error');
      return const SessionEndResult(
        SessionEndOutcome.failure,
        message: "We couldn't sign you out. Please try again.",
      );
    }
  }
}
