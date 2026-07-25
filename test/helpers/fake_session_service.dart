// Fake in-memory SessionService for tests that exercise the Logout flow
// without depending on the real secure-storage-backed implementation.

import 'dart:async';

import 'package:anc_fabrics/services/session_service.dart';

class FakeSessionService implements SessionService {
  FakeSessionService({this.error, this.pending, bool loggedIn = false})
    : _isLoggedIn = loggedIn;

  /// When set, thrown from `endSession` instead of resolving. Ignored
  /// when [pending] is set.
  Object? error;

  /// When set, `endSession` awaits this instead of resolving immediately —
  /// lets tests hold a logout "in flight" to observe loading state and the
  /// duplicate-tap guard.
  final Completer<void>? pending;

  bool _isLoggedIn;
  int endSessionCallCount = 0;

  @override
  Future<bool> isLoggedIn() async => _isLoggedIn;

  @override
  Future<void> endSession() async {
    endSessionCallCount++;
    if (pending != null) {
      await pending!.future;
    }
    if (error != null) throw error!;
    _isLoggedIn = false;
  }
}
