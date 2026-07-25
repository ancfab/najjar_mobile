// Fake in-memory AuthSessionStore for AuthService tests — no real secure
// storage platform channel is exercised.

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/auth_session_store.dart';

class FakeAuthSessionStore implements AuthSessionStore {
  AuthSession? _saved;

  /// Every session ever passed to [save], in call order.
  final List<AuthSession> savedSessions = [];

  /// When set, thrown from [save] instead of performing the save.
  Object? saveError;

  int saveCallCount = 0;
  int clearCallCount = 0;

  /// When set, [save] awaits this future before recording the save,
  /// letting tests observe that a caller does not see the save as complete
  /// until it actually resolves.
  Future<void>? saveGate;

  @override
  Future<void> save(AuthSession session) async {
    saveCallCount++;
    if (saveGate != null) await saveGate;
    if (saveError != null) throw saveError!;
    _saved = session;
    savedSessions.add(session);
  }

  @override
  Future<AuthSession?> read() async => _saved;

  @override
  Future<bool> hasValidSession() async => _saved != null;

  @override
  Future<void> clear() async {
    clearCallCount++;
    _saved = null;
  }
}
