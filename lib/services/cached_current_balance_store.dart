import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/cached_current_balance.dart';
import 'auth_session_store.dart';
import 'current_balance_service.dart';
import 'secure_auth_session_store.dart'
    show
        FlutterSecureKeyValueStore,
        SecureAuthSessionStore,
        SecureKeyValueStore;

/// Purpose: The app's single seam for remembering the last Current Balance
/// computed for the signed-in account, so `HomeScreen` can render a figure
/// immediately on open instead of waiting out a full ledger sweep on a slow
/// connection.
///
/// Responsibilities:
/// - Scope every read/write to the authenticated `userId` it resolves
///   itself from the stored session, so one device signing in as two ANC
///   accounts never shows one account's balance to the other.
/// - Resolve [load] to `null` for "nothing cached for this account" and for
///   any unreadable/corrupt entry — never throw, and never return a
///   fabricated balance.
/// - Swallow [save] failures: a cache that could not be written changes
///   nothing about the live figure already on screen.
///
/// Must not:
/// - Be consulted as the authoritative balance. Everything it returns is
///   last-known data that the UI must label as such once a refresh has
///   failed (see `HomeScreen._loadCurrentBalance`).
abstract interface class CachedCurrentBalanceStore {
  /// The signed-in account's cached balance, or `null` when there is none
  /// (including when no session is readable).
  Future<CachedCurrentBalance?> load();

  /// Records [amount] as the signed-in account's last computed balance,
  /// stamped with the current time. Never throws.
  Future<void> save(CurrentBalanceAmount amount);
}

/// Default [CachedCurrentBalanceStore]: one JSON envelope per `userId`,
/// namespaced under [_keyFor], in the same secure storage
/// [SecureAuthSessionStore] uses — this is account-specific financial
/// information, not a device-level preference like locale or scan history,
/// so plain `SharedPreferences` would not be appropriate.
///
/// Like `SecureLocalCustomerProfileStore`, an entry deliberately survives
/// logout: it is keyed by `userId`, so the same account finds its last
/// known balance again on the next sign-in, and a different account never
/// sees it.
class SecureCachedCurrentBalanceStore implements CachedCurrentBalanceStore {
  SecureCachedCurrentBalanceStore({
    SecureKeyValueStore? secureStore,
    AuthSessionStore? sessionStore,
  }) : _secureStore = secureStore ?? FlutterSecureKeyValueStore(),
       _sessionStore = sessionStore ?? SecureAuthSessionStore();

  final SecureKeyValueStore _secureStore;
  final AuthSessionStore _sessionStore;

  static const String _keyPrefix = 'anc_cached_current_balance_v1_';

  static String _keyFor(int userId) => '$_keyPrefix$userId';

  /// Exposes the exact storage key for a `userId`, for tests only — never
  /// used by production code, which always goes through [load]/[save].
  @visibleForTesting
  static String keyForTesting(int userId) => _keyFor(userId);

  @override
  Future<CachedCurrentBalance?> load() async {
    final key = await _currentKey();
    if (key == null) return null;

    final String? raw;
    try {
      raw = await _secureStore.read(key);
    } catch (_) {
      // A storage-read failure is treated exactly like "nothing cached":
      // the live fetch is already under way, and there is nothing to gain
      // by escalating a failed convenience read into a thrown exception.
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

    final cached = CachedCurrentBalance.fromJson(decoded);
    if (cached == null) await _deleteQuietly(key);
    return cached;
  }

  @override
  Future<void> save(CurrentBalanceAmount amount) async {
    final key = await _currentKey();
    if (key == null) return;

    final envelope = CachedCurrentBalance(
      amount: amount,
      cachedAt: DateTime.now().toUtc(),
    );
    try {
      await _secureStore.write(key, jsonEncode(envelope.toJson()));
    } catch (_) {
      // Intentionally ignored; see the interface's doc comment.
    }
  }

  /// The storage key for the currently signed-in account, or `null` when no
  /// session can be read — in which case there is no account to scope a
  /// cache entry to, and both [load] and [save] become no-ops rather than
  /// falling back to an unscoped key that two accounts could share.
  Future<String?> _currentKey() async {
    try {
      final session = await _sessionStore.read();
      if (session == null) return null;
      return _keyFor(session.userId);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort deletion of a secure entry already known to hold
  /// unreadable data — mirrors `SecureLocalCustomerProfileStore`'s. A
  /// failure here doesn't change the fact that [load] found nothing usable.
  Future<void> _deleteQuietly(String key) async {
    try {
      await _secureStore.delete(key);
    } catch (_) {
      // Intentionally ignored; see doc comment above.
    }
  }
}
