import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// How an [AvatarUploadService.updateAvatar] attempt resolved.
enum AvatarUpdateOutcome {
  /// The confirmed avatar was accepted and stored (locally — see
  /// [AvatarUpdateResult.isLocalOnly] — until a real backend exists).
  success,

  /// The avatar could not be stored/uploaded.
  failure,
}

class AvatarUpdateResult {
  const AvatarUpdateResult(
    this.outcome, {
    this.localPath,
    this.message,
    this.isLocalOnly = false,
  });

  final AvatarUpdateOutcome outcome;

  /// Stable local path the new avatar was written to, when [outcome] is
  /// [AvatarUpdateOutcome.success].
  final String? localPath;

  /// Optional user-safe message describing the outcome — never a stack
  /// trace or other implementation detail.
  final String? message;

  /// True when this result came from the local/mock implementation rather
  /// than a real backend upload. [EditProfileScreen] uses this to avoid
  /// ever describing a local-only save as a server "upload".
  final bool isLocalOnly;

  bool get succeeded => outcome == AvatarUpdateOutcome.success;
}

/// Confirms the user's cropped avatar selection ("Use Photo") and makes it
/// the active profile avatar. This is the seam screens depend on — they
/// never see whether that happens via a real backend upload or (today) a
/// local/mock implementation.
///
/// TODO(api): Replace the local avatar implementation when the
/// profile-media contract is available. Confirm the upload endpoint/method,
/// multipart field name, authentication headers, supported formats and
/// file-size limits, required image dimensions/compression, response
/// avatar URL field, cache-invalidation/versioning behavior,
/// previous-avatar deletion rules, and expected backend
/// validation/error responses.
abstract class AvatarUploadService {
  Future<AvatarUpdateResult> updateAvatar(String croppedImagePath);
}

/// TODO(api): No real avatar-upload backend exists anywhere in this project
/// yet — there is no API base URL, multipart request/response contract, or
/// authentication requirement documented or implemented for it (same gap as
/// `UnavailableProfileService` for profile text fields). This implementation
/// is NOT production-ready: it performs no network call. It copies the
/// already-cropped, already-confirmed image into this app's own stable
/// local storage (not the picker/cropper's temporary cache path) purely so
/// the picked avatar can be demonstrated and survive app restarts during
/// frontend development. Replace it with a real [AvatarUploadService]
/// implementation once the avatar upload endpoint and payload contract are
/// confirmed by product/backend — see the TODO(api) on
/// [AvatarUploadService] above for exactly what needs to be confirmed
/// first.
class LocalAvatarUploadService implements AvatarUploadService {
  const LocalAvatarUploadService();

  static const String _avatarsSubdirectory = 'avatars';
  static const String _avatarFileName = 'current_avatar.jpg';

  @override
  Future<AvatarUpdateResult> updateAvatar(String croppedImagePath) async {
    try {
      final sourceFile = File(croppedImagePath);
      if (!await sourceFile.exists()) {
        return const AvatarUpdateResult(AvatarUpdateOutcome.failure);
      }

      final supportDir = await getApplicationSupportDirectory();
      final avatarsDir = Directory('${supportDir.path}/$_avatarsSubdirectory');
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }

      final destinationPath = '${avatarsDir.path}/$_avatarFileName';
      // Overwrites any previously stored avatar at the same stable path.
      await sourceFile.copy(destinationPath);

      return AvatarUpdateResult(
        AvatarUpdateOutcome.success,
        localPath: destinationPath,
        isLocalOnly: true,
      );
    } catch (error) {
      // Technical detail only — never shown to the user.
      debugPrint('Local avatar update failed: $error');
      return const AvatarUpdateResult(AvatarUpdateOutcome.failure);
    }
  }
}
