import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_service.dart';

/// Single shared source of truth for the signed-in user's avatar image,
/// listened to by every screen that shows the current-user avatar (Home
/// header, Profile, Account Balance header, Invoice Details header, ...) so
/// a confirmed avatar change is reflected everywhere immediately without
/// each screen tracking its own copy of the image state.
///
/// Holds only a local file reference: see the TODO(api) on
/// [LocalAvatarUploadService] and on [restorePersisted] below for what
/// changes once a real backend avatar URL exists.
class CurrentUserAvatarController extends ChangeNotifier {
  CurrentUserAvatarController();

  File? _avatarFile;

  /// The current avatar file, or `null` when no avatar has been set (or it
  /// was cleared at logout) — screens fall back to their existing
  /// initials/icon placeholder in that case.
  File? get avatarFile => _avatarFile;

  /// Convenience [ImageProvider] for the current avatar, or `null` when
  /// none is set.
  ImageProvider? get imageProvider =>
      _avatarFile == null ? null : FileImage(_avatarFile!);

  /// Sets the active avatar to the file at [path] (expected to already be
  /// in stable, app-owned storage — see `LocalAvatarUploadService`) and
  /// persists the reference so [restorePersisted] can restore it on the
  /// next app launch.
  Future<void> setAvatarPath(String path) async {
    _avatarFile = File(path);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SessionStorageKeys.localAvatarPath, path);
    } catch (error) {
      // Technical detail only — the in-memory avatar is already updated
      // and visible; only the cross-restart persistence step failed.
      debugPrint('Failed to persist local avatar path: $error');
    }
  }

  /// Clears the current avatar, both in memory and from stable storage.
  /// Called on logout so one user never sees another user's locally
  /// cached avatar after a subsequent login. Best-effort: a failure to
  /// delete the underlying file does not prevent it from disappearing from
  /// the UI.
  Future<void> clear() async {
    final previousFile = _avatarFile;
    _avatarFile = null;
    notifyListeners();

    if (previousFile != null) {
      try {
        if (await previousFile.exists()) await previousFile.delete();
      } catch (error) {
        debugPrint('Failed to delete local avatar file: $error');
      }
    }
  }

  /// Restores a previously persisted local avatar reference (if any) so it
  /// reappears without the user having to re-select it after an app
  /// restart. Safe to call multiple times; does nothing if no path was
  /// persisted or the file no longer exists.
  ///
  /// TODO(api): This restores only the temporary local/mock avatar
  /// reference (see `LocalAvatarUploadService`). Once the backend returns a
  /// real avatar URL as part of the authenticated user's profile, replace
  /// this with loading that URL after login/profile-fetch instead of
  /// reading local device storage.
  Future<void> restorePersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(SessionStorageKeys.localAvatarPath);
      if (path == null) return;

      final file = File(path);
      if (await file.exists()) {
        _avatarFile = file;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Failed to restore local avatar: $error');
    }
  }
}

/// App-wide singleton, used as the default [CurrentUserAvatarController] by
/// every screen that displays or updates the current-user avatar.
/// Constructor parameters on those screens still accept an explicit
/// controller override, so widget tests can inject a fresh instance instead
/// of sharing this mutable singleton across test cases.
final CurrentUserAvatarController currentUserAvatarController =
    CurrentUserAvatarController();
