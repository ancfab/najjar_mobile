import 'package:image_picker/image_picker.dart';

/// Where a picked avatar image should come from.
enum AvatarImageSource { camera, gallery }

/// A successfully picked (not yet cropped/validated) avatar image.
class PickedAvatarImage {
  const PickedAvatarImage(this.path);

  /// Absolute path to the picked file. On some platforms this is a
  /// temporary/cache location, so callers must not rely on it surviving
  /// past the current avatar-selection flow.
  final String path;
}

/// Launches the platform camera or photo gallery to select a single image
/// for the profile avatar. Isolated behind this abstraction so
/// [EditProfileScreen]-level code (and its widget tests) never depends on
/// the `image_picker` platform channel directly.
abstract class AvatarPickerService {
  /// Returns the picked image, or `null` if the user cancelled the picker.
  ///
  /// May throw if the platform picker itself fails (e.g. no camera
  /// available, or the OS denies the request); callers are responsible for
  /// catching this and showing user-facing feedback.
  Future<PickedAvatarImage?> pickImage(AvatarImageSource source);
}

/// Real [AvatarPickerService] backed by the `image_picker` plugin.
///
/// `maxWidth`/`maxHeight` are set so the plugin downsamples (and
/// EXIF-corrects the orientation of) the image during the platform-side
/// pick itself, before it ever reaches Dart — this keeps the app from ever
/// decoding a full-resolution camera photo into memory.
class ImagePickerAvatarPickerService implements AvatarPickerService {
  const ImagePickerAvatarPickerService();

  static const double _maxDimension = 2048;
  static const int _imageQuality = 90;

  @override
  Future<PickedAvatarImage?> pickImage(AvatarImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source == AvatarImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _imageQuality,
    );
    if (file == null) return null;
    return PickedAvatarImage(file.path);
  }
}
