// Fake AvatarUploadService for tests that exercise the Edit Profile avatar
// flow without depending on the real local/mock file-copy implementation.

import 'dart:async';

import 'package:anc_fabrics/services/avatar_upload_service.dart';

class FakeAvatarUploadService implements AvatarUploadService {
  FakeAvatarUploadService({this.result, this.pending});

  /// An [AvatarUpdateResult] to resolve with, or an [Exception] to throw.
  /// Defaults to a success result echoing the submitted path when null.
  /// Ignored when [pending] is set.
  Object? result;

  final Completer<AvatarUpdateResult>? pending;

  final List<String> submittedPaths = [];

  @override
  Future<AvatarUpdateResult> updateAvatar(String croppedImagePath) async {
    submittedPaths.add(croppedImagePath);
    if (pending != null) return pending!.future;
    if (result is Exception) throw result as Exception;
    return result as AvatarUpdateResult? ??
        AvatarUpdateResult(
          AvatarUpdateOutcome.success,
          localPath: croppedImagePath,
          message: 'Profile photo updated on this device.',
          isLocalOnly: true,
        );
  }
}
