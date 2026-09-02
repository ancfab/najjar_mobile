import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/local_customer_profile.dart';
import 'secure_auth_session_store.dart'
    show FlutterSecureKeyValueStore, SecureKeyValueStore;

/// Purpose: The app's single seam for persisting and retrieving the
/// locally-owned customer-profile display fields (full name, email,
/// company, business address — see [LocalCustomerProfile]), scoped to one
/// authenticated account at a time.
///
/// Responsibilities:
/// - Scope every read/write/clear to the caller-supplied authenticated
///   `userId` (see `AuthSession.userId`) so one device signing in as two
///   different ANC accounts never mixes, nor leaks, their profile data —
///   never keyed by `bc_customer_no` or any other reinterpreted
///   identifier.
/// - Resolve [load] to `null` for "no profile saved yet for this userId"
///   and for any unreadable/corrupt stored entry — never throw.
///
/// Must not:
/// - Be used for `AuthSession` fields (username/phone/country/client_id/
///   bc_customer_no/must_change_password/avatar_url) — those keep their
///   own, separate, secure-session storage.
/// - Be used for Business Central `CustomerDetails` (balance/credit
///   figures) — that endpoint's contract requires it stay a fresh,
///   never-cached fetch.
abstract interface class LocalCustomerProfileStore {
  Future<LocalCustomerProfile?> load(int userId);

  Future<void> save(int userId, LocalCustomerProfile profile);

  Future<void> clear(int userId);
}

/// Default [LocalCustomerProfileStore]: one JSON envelope per `userId`,
/// namespaced under [_keyFor], stored in the same secure storage
/// [SecureAuthSessionStore] uses (`flutter_secure_storage`) — this is
/// account-specific customer information, not a device-level preference
/// like locale or scan history, so plain `SharedPreferences` would not be
/// appropriate.
class SecureLocalCustomerProfileStore implements LocalCustomerProfileStore {
  SecureLocalCustomerProfileStore({SecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSecureKeyValueStore();

  final SecureKeyValueStore _secureStore;

  static const String _keyPrefix = 'anc_local_customer_profile_v1_';

  static String _keyFor(int userId) => '$_keyPrefix$userId';

  /// Exposes the exact storage key for a `userId`, for tests only — never
  /// used by production code, which always goes through [load]/[save]/
  /// [clear].
  @visibleForTesting
  static String keyForTesting(int userId) => _keyFor(userId);

  @override
  Future<LocalCustomerProfile?> load(int userId) async {
    final key = _keyFor(userId);

    final String? raw;
    try {
      raw = await _secureStore.read(key);
    } catch (_) {
      // A storage-read failure is treated the same as "no profile saved
      // yet" — this is a low-stakes local display cache, not the
      // authoritative session, so there is nothing to gain by escalating
      // it into a thrown exception every caller would have to handle.
      return null;
    }
    if (raw == null || raw.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      await _deleteQuietly(key);
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      await _deleteQuietly(key);
      return null;
    }

    return LocalCustomerProfile.fromJson(decoded);
  }

  @override
  Future<void> save(int userId, LocalCustomerProfile profile) {
    return _secureStore.write(_keyFor(userId), jsonEncode(profile.toJson()));
  }

  @override
  Future<void> clear(int userId) => _secureStore.delete(_keyFor(userId));

  /// Best-effort deletion of a secure entry already known to hold
  /// unreadable data — mirrors `SecureAuthSessionStore._deleteQuietly`. A
  /// failure here doesn't change the fact that [load] found nothing usable,
  /// so it is swallowed rather than escalated.
  Future<void> _deleteQuietly(String key) async {
    try {
      await _secureStore.delete(key);
    } catch (_) {
      // Intentionally ignored; see doc comment above.
    }
  }
}
