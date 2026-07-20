// Fake AvatarPermissionService for tests that exercise the Edit Profile
// avatar flow without depending on the real permission_handler platform
// channel.

import 'package:anc_fabrics/services/avatar_permission_service.dart';

class FakeAvatarPermissionService implements AvatarPermissionService {
  FakeAvatarPermissionService({
    this.cameraStatus = AvatarPermissionStatus.granted,
    this.galleryStatus = AvatarPermissionStatus.granted,
  });

  AvatarPermissionStatus cameraStatus;
  AvatarPermissionStatus galleryStatus;

  int cameraRequestCount = 0;
  int galleryRequestCount = 0;
  int openSettingsCallCount = 0;

  @override
  Future<AvatarPermissionStatus> requestCameraPermission() async {
    cameraRequestCount++;
    return cameraStatus;
  }

  @override
  Future<AvatarPermissionStatus> requestGalleryPermission() async {
    galleryRequestCount++;
    return galleryStatus;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return true;
  }
}
