import 'package:permission_handler/permission_handler.dart' as ph;

/// Result of requesting the camera permission needed to run the QR/barcode
/// scanner on the Scan Stock screen.
enum ScanCameraPermissionStatus {
  /// Access was granted; the scanner can start.
  granted,

  /// The user denied the request. It is safe to ask again later.
  denied,

  /// The OS denies the request outright (e.g. parental controls/MDM
  /// restriction) — asking again will not help.
  restricted,

  /// The user denied the request and the OS will not show the prompt
  /// again. The only way forward is the app's Settings page.
  permanentlyDenied,
}

/// Requests the camera permission needed for QR/barcode scanning, isolated
/// behind this abstraction so [ScanStockScreen] (and its widget tests)
/// don't depend on the `permission_handler` platform channel directly.
abstract class ScanCameraPermissionService {
  Future<ScanCameraPermissionStatus> requestCameraPermission();

  /// Opens the app's Settings page, for the permanently-denied case.
  /// Returns whether the settings page could be opened.
  Future<bool> openSettings();
}

/// Real [ScanCameraPermissionService] backed by the `permission_handler`
/// plugin.
class PermissionHandlerScanCameraPermissionService
    implements ScanCameraPermissionService {
  const PermissionHandlerScanCameraPermissionService();

  @override
  Future<ScanCameraPermissionStatus> requestCameraPermission() async {
    final status = await ph.Permission.camera.request();
    return _mapStatus(status);
  }

  ScanCameraPermissionStatus _mapStatus(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
      // `limited`/`provisional` are photo-library-specific iOS states that
      // permission_handler's shared enum still technically allows here;
      // the camera permission itself is never partially granted.
      case ph.PermissionStatus.limited:
      case ph.PermissionStatus.provisional:
        return ScanCameraPermissionStatus.granted;
      case ph.PermissionStatus.restricted:
        return ScanCameraPermissionStatus.restricted;
      case ph.PermissionStatus.permanentlyDenied:
        return ScanCameraPermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.denied:
        return ScanCameraPermissionStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() => ph.openAppSettings();
}
