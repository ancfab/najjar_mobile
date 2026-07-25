// Fake in-memory SecureKeyValueStore for SecureAuthSessionStore tests — no
// real iOS Keychain / Android Keystore platform channel is exercised.

import 'package:anc_fabrics/services/secure_auth_session_store.dart';

class FakeSecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _values = {};

  /// When set, thrown from [read] instead of performing the read.
  Object? readError;

  /// When set, thrown from [write] instead of performing the write.
  Object? writeError;

  /// When set, thrown from [delete] instead of performing the delete.
  Object? deleteError;

  int deleteCallCount = 0;

  /// Directly seeds a stored value, bypassing [write], so tests can set up
  /// malformed/missing persisted data.
  void seed(String key, String value) => _values[key] = value;

  bool containsKey(String key) => _values.containsKey(key);

  @override
  Future<String?> read(String key) async {
    if (readError != null) throw readError!;
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (writeError != null) throw writeError!;
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleteCallCount++;
    if (deleteError != null) throw deleteError!;
    _values.remove(key);
  }
}
