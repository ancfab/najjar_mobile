import 'auth_session.dart';

/// Purpose: The typed result [AuthService.uploadAvatar] returns, so a
/// future avatar-upload caller can distinguish success from failure —
/// and distinguish kinds of failure — without inspecting HTTP status codes,
/// exception types, or raw response bodies. Mirrors [AuthLoginResult]'s
/// shape.
///
/// Responsibilities:
/// - [UploadAvatarSuccess] carries the re-persisted [AuthSession] with the
///   refreshed `avatarUrl` (and every other identity field) on success.
/// - [UploadAvatarFailure] carries a small, stable [UploadAvatarFailureType]
///   plus, for [UploadAvatarFailureType.rejectedByServer] only, a safe
///   single message string suitable for inline display.
///
/// Must not:
/// - Carry a raw HTTP status code, [Exception], response body, or any
///   backend message not already vetted as safe to surface.
/// - Carry a token in any field or in [toString].
sealed class UploadAvatarResult {
  const UploadAvatarResult();
}

/// A successful avatar upload: the API call succeeded and the refreshed
/// [session] (with its new `avatarUrl`) has already been persisted through
/// `AuthSessionStore` before this is returned.
class UploadAvatarSuccess extends UploadAvatarResult {
  const UploadAvatarSuccess(this.session);

  final AuthSession session;

  @override
  String toString() => 'UploadAvatarSuccess(userId: ${session.userId})';
}

/// The small, stable set of ways an avatar-upload attempt can fail, safe
/// for a future caller to switch on directly.
enum UploadAvatarFailureType {
  /// No file exists at the given path — checked locally before any API
  /// call is made.
  fileNotFound,

  /// The file exceeds [ApiConfig.avatarMaxUploadBytes] — checked locally
  /// before any API call is made, per the confirmed 5 MB contract.
  fileTooLarge,

  /// The file's leading bytes don't match jpg/png/webp — checked locally,
  /// via signature (not filename extension), before any API call is made.
  unsupportedFormat,

  /// HTTP 422 with a validation error under `errors.avatar` — a
  /// server-side rejection reason not caught by the local pre-checks
  /// above.
  rejectedByServer,

  /// No session is currently stored, or the ANC API rejected the stored
  /// token with HTTP 401 (the local session is cleared in that case, same
  /// as `AuthService.confirmSession`/`updateProfile`).
  unauthorized,

  /// The request never reached the server, or no response was received
  /// (including a timeout).
  network,

  /// The ANC API reached but failed to service the request (HTTP 5xx, or
  /// another unexpected non-success status not covered above).
  serviceUnavailable,

  /// A response was received but its body did not match the expected
  /// shape.
  invalidResponse,

  /// The HTTP upload succeeded but persisting the refreshed session to
  /// secure storage failed, or the stored session could not be read.
  secureStorage,
}

/// A failed avatar-upload attempt. See [UploadAvatarFailureType] for what
/// each value means and what it must not imply.
class UploadAvatarFailure extends UploadAvatarResult {
  const UploadAvatarFailure(this.type, {this.message});

  final UploadAvatarFailureType type;

  /// The first safe message from the backend's `errors.avatar`, present
  /// only when [type] is [UploadAvatarFailureType.rejectedByServer].
  final String? message;

  @override
  String toString() => 'UploadAvatarFailure(type: $type)';
}
