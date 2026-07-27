// Fake in-memory LogoutService for tests that exercise the explicit-logout
// UI flow without depending on AuthService's real HTTP/secure-storage
// wiring.

import 'dart:async';

import 'package:anc_fabrics/services/logout_service.dart';

class FakeLogoutService implements LogoutService {
  FakeLogoutService({this.error, this.pending});

  /// When set, thrown from `logout` instead of resolving. Ignored when
  /// [pending] is set.
  Object? error;

  /// When set, `logout` awaits this instead of resolving immediately — lets
  /// tests hold a logout "in flight" to observe loading state and the
  /// duplicate-tap guard.
  final Completer<void>? pending;

  int logoutCallCount = 0;

  @override
  Future<void> logout() async {
    logoutCallCount++;
    if (pending != null) {
      await pending!.future;
    }
    if (error != null) throw error!;
  }
}
