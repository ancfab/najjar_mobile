// Fake SessionExpiryCoordinator for service-level tests: records
// invocations instead of touching real secure storage, the avatar
// controller, or the Navigator.

import 'package:anc_fabrics/services/session_expiry_coordinator.dart';

class FakeSessionExpiryCoordinator extends SessionExpiryCoordinator {
  int handleUnauthorizedCallCount = 0;

  @override
  Future<void> handleUnauthorized() async {
    handleUnauthorizedCallCount++;
  }
}
