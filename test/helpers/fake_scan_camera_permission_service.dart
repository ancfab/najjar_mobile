// Fake ScanCameraPermissionService for tests that exercise the Scan Stock
// screen's permission flow without depending on the real permission_handler
// platform channel.

import 'package:anc_fabrics/services/scan_camera_permission_service.dart';

class FakeScanCameraPermissionService implements ScanCameraPermissionService {
  FakeScanCameraPermissionService({
    this.status = ScanCameraPermissionStatus.granted,
  });

  ScanCameraPermissionStatus status;

  int requestCount = 0;
  int openSettingsCallCount = 0;

  @override
  Future<ScanCameraPermissionStatus> requestCameraPermission() async {
    requestCount++;
    return status;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return true;
  }
}
