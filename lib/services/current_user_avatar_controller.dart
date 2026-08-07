import 'package:flutter/widgets.dart';

/// Single shared source of truth for the signed-in user's avatar image,
/// listened to by every screen that shows the current-user avatar (Home
/// header, Profile, Account Balance header, Invoice Details header, ...) so
/// a confirmed avatar change is reflected everywhere immediately without
/// each screen tracking its own copy of the image state.
///
/// Backed by a plain network URL — the authenticated user's `avatarUrl`
/// (see `AuthenticatedUser`/`AuthSession`), which the ANC API already
/// persists server-side and `SecureAuthSessionStore` already persists
/// locally across restarts. This controller holds no independent
/// persistence of its own: it is refreshed from the confirmed session on
/// cold start (`main.dart`, after `AuthService.confirmSession`) and after
/// any successful `AuthService.updateProfile`/`uploadAvatar` call, and
/// cleared on logout/session-invalidation the same way it always has been.
class CurrentUserAvatarController extends ChangeNotifier {
  CurrentUserAvatarController();

  String? _avatarUrl;

  /// The current avatar URL, or `null` when no avatar has been set (or it
  /// was cleared at logout) — screens fall back to their existing
  /// initials/icon placeholder in that case.
  String? get avatarUrl => _avatarUrl;

  /// Convenience [ImageProvider] for the current avatar, or `null` when
  /// none is set.
  ImageProvider? get imageProvider =>
      _avatarUrl == null ? null : NetworkImage(_avatarUrl!);

  /// Sets the active avatar to [url] (or clears it, when `null`) and
  /// notifies listeners.
  ///
  /// Evicts any previously cached image for the *old* URL from
  /// [PaintingBinding.imageCache] first — so a replacement avatar is shown
  /// immediately even if the backend happens to return the same URL string
  /// for the new image (this app never assumes a cache-busting query
  /// parameter or filename change on the backend's part; eviction is a
  /// purely client-side guarantee that doesn't depend on that).
  void setAvatarUrl(String? url) {
    final previousUrl = _avatarUrl;
    if (previousUrl != null) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(previousUrl));
    }
    _avatarUrl = url;
    notifyListeners();
  }

  /// Clears the current avatar. Called on logout/session-invalidation so
  /// one user never sees another user's avatar after a subsequent login.
  void clear() => setAvatarUrl(null);
}

/// App-wide singleton, used as the default [CurrentUserAvatarController] by
/// every screen that displays or updates the current-user avatar.
/// Constructor parameters on those screens still accept an explicit
/// controller override, so widget tests can inject a fresh instance instead
/// of sharing this mutable singleton across test cases.
final CurrentUserAvatarController currentUserAvatarController =
    CurrentUserAvatarController();
