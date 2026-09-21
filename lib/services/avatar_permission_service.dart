import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'avatar_picker_service.dart';

/// Result of requesting the permission needed for a given [AvatarImageSource].
enum AvatarPermissionStatus {
  /// Full access was granted; proceed with the picker.
  granted,

  /// iOS-only partial photo-library access; the gallery picker can still be
  /// used.
  limited,

  /// The user denied the request. It is safe to ask again later.
  denied,

  /// The OS denies the request outright (iOS "restricted", e.g. parental
  /// controls) — asking again will not help.
  restricted,

  /// The user denied the request and the OS will not show the prompt
  /// again. The only way forward is the app's Settings page.
  permanentlyDenied,
}

/// Requests the platform permission required to use the camera or photo
/// gallery for avatar selection, isolated behind this abstraction so
/// screens (and their widget tests) don't depend on the `permission_handler`
/// platform channel directly.
abstract class AvatarPermissionService {
  Future<AvatarPermissionStatus> requestCameraPermission();

  Future<AvatarPermissionStatus> requestGalleryPermission();

  /// Opens the app's Settings page, for the permanently-denied case. Returns
  /// whether the settings page could be opened.
  Future<bool> openSettings();
}

/// Real [AvatarPermissionService] backed by the `permission_handler` plugin.
///
/// On Android, gallery access needs no runtime permission: `image_picker`
/// launches the system Photo Picker, which grants access to only the image
/// the user picks. The app deliberately doesn't declare `READ_MEDIA_IMAGES`
/// (see AndroidManifest.xml), so requesting `Permission.photos` there would
/// always come back denied and block the picker. On iOS, gallery access
/// still requests `Permission.photos`.
class PermissionHandlerAvatarPermissionService
    implements AvatarPermissionService {
  const PermissionHandlerAvatarPermissionService();

  @override
  Future<AvatarPermissionStatus> requestCameraPermission() =>
      _request(ph.Permission.camera);

  @override
  Future<AvatarPermissionStatus> requestGalleryPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AvatarPermissionStatus.granted;
    }
    return _request(ph.Permission.photos);
  }

  Future<AvatarPermissionStatus> _request(ph.Permission permission) async {
    final status = await permission.request();
    return _mapStatus(status);
  }

  AvatarPermissionStatus _mapStatus(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
        return AvatarPermissionStatus.granted;
      case ph.PermissionStatus.limited:
        return AvatarPermissionStatus.limited;
      case ph.PermissionStatus.restricted:
        return AvatarPermissionStatus.restricted;
      case ph.PermissionStatus.permanentlyDenied:
        return AvatarPermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.denied:
      case ph.PermissionStatus.provisional:
        return AvatarPermissionStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() => ph.openAppSettings();
}
