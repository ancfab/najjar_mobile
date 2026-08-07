import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/current_user_avatar_controller.dart';
import '../services/session_messages.dart';

/// Purpose: The one shared "the stored token was just confirmed dead"
/// UI reaction for screens that call `AuthService.updateProfile`/
/// `changePassword`/`uploadAvatar` directly and get back that method's own
/// `unauthorized` outcome.
///
/// These three `AuthService` methods already clear the local secure
/// session themselves on HTTP 401 (see their doc comments) and
/// deliberately never depend on `SessionExpiryCoordinator` (a passive
/// mechanism for services reached indirectly, e.g. Business Central data
/// services) — the caller here is a screen already in the middle of a
/// direct, user-initiated request, so it owns clearing the remaining
/// in-memory state (the avatar) and navigating away itself, the same way
/// `EditProfileScreen._handleLogout` already does for explicit logout.
///
/// Callers should check their own `mounted`/`context.mounted` immediately
/// before calling this, the same as before any other post-`await` widget
/// interaction — this does no further asynchronous work of its own, so it
/// does not repeat that check.
///
/// Must not:
/// - Attempt any further remote call — the token is already confirmed
///   dead server-side.
void handleUnauthorizedResult(
  BuildContext context,
  CurrentUserAvatarController avatarController,
) {
  avatarController.clear();
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) =>
          const LoginScreen(startupMessage: LoginStartupMessage.sessionExpired),
    ),
    (route) => false,
  );
}
