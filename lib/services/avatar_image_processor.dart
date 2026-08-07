import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../utils/image_format_sniffer.dart';

/// Why a picked file was rejected by [AvatarImageProcessor.validate] —
/// mapped to a localized, user-safe message by the caller (see
/// `EditProfileScreen`) rather than carrying a fixed-language message here.
enum AvatarImageValidationReason {
  fileNotFound,
  emptyFile,
  tooLarge,
  unreadableFile,
  unsupportedFormat,
  corruptImage,
}

/// Thrown by [AvatarImageProcessor.validate] when a picked file can't be
/// accepted as an avatar.
class AvatarImageValidationException implements Exception {
  const AvatarImageValidationException(this.reason);

  final AvatarImageValidationReason reason;

  @override
  String toString() => 'AvatarImageValidationException: $reason';
}

/// Validates a picked (pre-crop) avatar image before it is handed to the
/// cropper, isolated behind this abstraction so tests can simulate
/// validation failures without needing a real corrupt file on disk.
abstract class AvatarImageProcessor {
  /// Throws [AvatarImageValidationException] if [path] is not a file this
  /// app can safely accept as an avatar source. Returns normally when the
  /// file is valid.
  Future<void> validate(String path);
}

/// Real [AvatarImageProcessor]: confirms the file exists, is within a sane
/// size budget, and decodes as an actual image (rejecting non-image files
/// and corrupt data) before it's passed to the cropper.
///
/// Deliberately does not re-implement EXIF-orientation correction: the
/// upstream picker (see `AvatarPickerService`) already requests a bounded
/// `maxWidth`/`maxHeight`, which on both Android and iOS causes the native
/// picker to decode with the correct orientation applied — so by the time a
/// path reaches here it is already right-side-up and small enough to
/// decode safely for validation.
class DefaultAvatarImageProcessor implements AvatarImageProcessor {
  const DefaultAvatarImageProcessor();

  /// Generous ceiling on the *pre-crop* source file, well above what the
  /// picker's own downsampling should ever produce — this only exists to
  /// reject something unexpectedly huge before it's read into memory.
  static const int _maxSourceBytes = 20 * 1024 * 1024;

  @override
  Future<void> validate(String path) async {
    final file = File(path);

    if (!await file.exists()) {
      throw const AvatarImageValidationException(
        AvatarImageValidationReason.fileNotFound,
      );
    }

    final length = await file.length();
    if (length <= 0) {
      throw const AvatarImageValidationException(
        AvatarImageValidationReason.emptyFile,
      );
    }
    if (length > _maxSourceBytes) {
      throw const AvatarImageValidationException(
        AvatarImageValidationReason.tooLarge,
      );
    }

    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      throw const AvatarImageValidationException(
        AvatarImageValidationReason.unreadableFile,
      );
    }

    if (!hasSupportedAvatarSourceSignature(bytes)) {
      throw const AvatarImageValidationException(
        AvatarImageValidationReason.unsupportedFormat,
      );
    }

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      await codec.getNextFrame();
    } catch (_) {
      throw const AvatarImageValidationException(
        AvatarImageValidationReason.corruptImage,
      );
    }
  }
}
