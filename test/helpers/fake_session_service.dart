// Fake in-memory SessionService for tests that exercise the Logout flow
// without depending on the real SharedPreferences-backed implementation.

import 'dart:async';

import 'package:anc_fabrics/services/session_service.dart';

class FakeSessionService implements SessionService {
  FakeSessionService({this.result, this.pending, bool loggedIn = false})
    : _isLoggedIn = loggedIn;

  /// A [SessionEndResult] to resolve `endSession` with, or an [Exception]
  /// to throw. Ignored when [pending] is set.
  Object? result;

  /// When set, `endSession` awaits this instead of resolving immediately —
  /// lets tests hold a logout "in flight" to observe loading state and the
  /// duplicate-tap guard.
  final Completer<SessionEndResult>? pending;

  bool _isLoggedIn;
  int endSessionCallCount = 0;

  @override
  Future<bool> isLoggedIn() async => _isLoggedIn;

  @override
  Future<void> startSession() async {
    _isLoggedIn = true;
  }

  @override
  Future<SessionEndResult> endSession() async {
    endSessionCallCount++;
    final outcome = await _resolveOutcome();
    if (outcome.succeeded) _isLoggedIn = false;
    return outcome;
  }

  Future<SessionEndResult> _resolveOutcome() async {
    if (pending != null) return pending!.future;
    if (result is Exception) throw result as Exception;
    return result as SessionEndResult? ?? SessionEndResult.success;
  }
}
