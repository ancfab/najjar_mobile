// Fake AvatarCropperService for tests that exercise the Edit Profile avatar
// flow without depending on the real image_cropper platform channel.

import 'dart:async';

import 'package:anc_fabrics/services/avatar_cropper_service.dart';

class FakeAvatarCropperService implements AvatarCropperService {
  FakeAvatarCropperService({
    this.resultPath,
    this.cancelled = false,
    this.throwError,
    this.pending,
  });

  /// Path to resolve with. Defaults to echoing the source path unchanged
  /// when null, [cancelled] is false, and [throwError] is null.
  String? resultPath;

  /// When true, simulates the user cancelling cropping (`cropToSquare`
  /// resolves with null).
  bool cancelled;

  /// When set, `cropToSquare` throws this instead of resolving.
  Exception? throwError;

  /// When set, `cropToSquare` awaits this instead of resolving immediately.
  final Completer<String?>? pending;

  final List<String> croppedSourcePaths = [];

  @override
  Future<String?> cropToSquare(
    String sourcePath, {
    String toolbarTitle = 'Crop Photo',
  }) async {
    croppedSourcePaths.add(sourcePath);
    if (pending != null) return pending!.future;
    if (throwError != null) throw throwError!;
    if (cancelled) return null;
    return resultPath ?? sourcePath;
  }
}
