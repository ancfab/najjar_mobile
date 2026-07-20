import 'package:image_cropper/image_cropper.dart';

/// Lets the user crop a picked image to a square before it becomes the
/// profile avatar, isolated behind this abstraction so screens (and their
/// widget tests) don't depend on the `image_cropper` platform channel
/// directly.
abstract class AvatarCropperService {
  /// Returns the cropped image's file path, or `null` if the user
  /// cancelled cropping.
  ///
  /// May throw if the platform cropper itself fails; callers are
  /// responsible for catching this and showing user-facing feedback.
  Future<String?> cropToSquare(String sourcePath);
}

/// Real [AvatarCropperService] backed by the `image_cropper` plugin.
///
/// Locks the crop UI to a 1:1 square (matching the circular avatar it will
/// be displayed in) and compresses the output so an unnecessarily large
/// file is never produced. Per the plugin's own documentation, the result
/// file is written to a temporary/cache directory — it is the caller's
/// responsibility to copy it somewhere stable if it needs to survive
/// beyond the current flow (see `AvatarUploadService`).
class ImageCropperAvatarCropperService implements AvatarCropperService {
  const ImageCropperAvatarCropperService();

  static const int _maxDimension = 1024;
  static const int _compressQuality = 85;

  @override
  Future<String?> cropToSquare(String sourcePath) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: _compressQuality,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: true,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    return cropped?.path;
  }
}
