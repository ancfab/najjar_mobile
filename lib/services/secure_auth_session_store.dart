import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth/auth_session.dart';
import 'auth_session_store.dart';
import 'session_storage_exception.dart';
import 'session_storage_keys.dart';

/// Purpose: The narrow secure key/value seam `SecureAuthSessionStore`
/// depends on, so unit tests can inject a fake instead of exercising a real
/// iOS Keychain / Android Keystore platform channel.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Default [SecureKeyValueStore], backed by `flutter_secure_storage`
/// (resolved version 10.3.1) using its plain default options on every
/// platform: no biometric enforcement (`AndroidOptions()`'s RSA-OAEP +
/// AES-GCM Keystore cipher, not `AndroidOptions.biometric(...)`), no custom
/// iOS `KeychainAccessibility` (the default `unlocked` value), and no
/// iCloud Keychain sync. Nothing in this phase's requirements calls for
/// biometric prompts, a different accessibility window, or cross-device
/// sync, so none are configured.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Purpose: Persists the authenticated ANC API session as one versioned
/// JSON envelope in platform-secure storage (iOS Keychain / Android
/// Keystore-backed encrypted storage).
///
/// Responsibilities:
/// - Serialize/deserialize one [AuthSession] under one namespaced secure
///   key ([_sessionKey]).
/// - Treat a missing key, an empty value, or malformed/incomplete JSON as
///   "no session" (returning `null` from [read]), best-effort deleting the
///   invalid entry so it can't wedge future reads.
/// - Raise [SessionStorageException] instead when the secure-storage
///   operation itself fails (a Keychain/Keystore/plugin I/O failure) —
///   never silently reporting that as "logged out".
/// - On [clear], delete the non-authoritative legacy
///   [SessionStorageKeys.isLoggedIn] SharedPreferences boolean first, then
///   the authoritative secure session key last, leaving every other
///   preference untouched. This ordering means a failure at either step
///   always leaves the secure token in place and reports failure — never a
///   partial clear that would be unsafe to navigate away on. See [clear].
///
/// Must not:
/// - Ever write session data to SharedPreferences.
/// - Log the token or the serialized session JSON.
class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  static const String _sessionKey = 'anc_auth_session_v1';

  @override
  Future<void> save(AuthSession session) async {
    // Programmer/model errors from toJson() (there are none expected in
    // practice) must surface unchanged, not be relabeled as a storage
    // failure below.
    final encoded = jsonEncode(session.toJson());

    await _wrapStorageFailure(
      SessionStorageOperation.write,
      () => _secureStore.write(_sessionKey, encoded),
    );
  }

  @override
  Future<AuthSession?> read() async {
    final raw = await _wrapStorageFailure(
      SessionStorageOperation.read,
      () => _secureStore.read(_sessionKey),
    );

    if (raw == null) return null;
    if (raw.isEmpty) {
      await _deleteQuietly();
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      await _deleteQuietly();
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      await _deleteQuietly();
      return null;
    }

    try {
      return AuthSession.fromJson(decoded);
    } on FormatException {
      await _deleteQuietly();
      return null;
    }
  }

  @override
  Future<bool> hasValidSession() async => await read() != null;

  @override
  Future<void> clear() async {
    await _wrapStorageFailure(SessionStorageOperation.clear, () async {
      // The non-authoritative legacy Boolean is removed first; the
      // authoritative secure key is removed last. A failure at either step
      // (thrown from within this one wrapped action) leaves the secure
      // token in place, so the caller can safely treat any thrown
      // SessionStorageException as "still signed in" and must not
      // navigate to Login.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(SessionStorageKeys.isLoggedIn);
      await _secureStore.delete(_sessionKey);
    });
  }

  /// Best-effort deletion of a secure entry already known to hold invalid
  /// data. A failure here doesn't change the fact that [read] found no
  /// usable session, so it is swallowed rather than escalated to
  /// [SessionStorageException].
  Future<void> _deleteQuietly() async {
    try {
      await _secureStore.delete(_sessionKey);
    } catch (_) {
      // Intentionally ignored; see doc comment above.
    }
  }

  /// Runs [action], mapping any failure that is not a programmer error
  /// ([ArgumentError]/[StateError]) into a [SessionStorageException] for
  /// [operation]. Programmer errors propagate unchanged rather than being
  /// mislabeled as a secure-storage failure.
  Future<T> _wrapStorageFailure<T>(
    SessionStorageOperation operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on StateError {
      rethrow;
    } catch (_) {
      throw SessionStorageException(operation);
    }
  }
}
