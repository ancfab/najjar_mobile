/// Purpose: The one typed failure `SecureAuthSessionStore` raises when the
/// underlying secure storage itself fails to complete an operation.
///
/// Responsibilities:
/// - Identify which operation failed via [operation].
/// - Expose a safe, generic [message] suitable for logs or a fallback UI
///   string.
///
/// Must not:
/// - Carry the session JSON, the token, or the password — in [message] or
///   [toString].
/// - Be used for missing/malformed persisted data; that is "no session",
///   not a storage failure, and must never reach this type.
/// - Be constructed by catching and relabeling a programmer error
///   (`ArgumentError`, `StateError`) — those must propagate unchanged.
enum SessionStorageOperation { read, write, clear }

class SessionStorageException implements Exception {
  const SessionStorageException(this.operation);

  final SessionStorageOperation operation;

  /// Short, generic, developer-facing description. Never derived from the
  /// underlying storage error's own message, which could echo back
  /// implementation detail this type must not carry.
  String get message => 'Secure session storage ${operation.name} failed.';

  @override
  String toString() => 'SessionStorageException: $message';
}
