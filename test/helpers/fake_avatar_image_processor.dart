// Fake AvatarImageProcessor for tests that exercise the Edit Profile avatar
// flow without needing a real (in)valid image file on disk.

import 'package:anc_fabrics/services/avatar_image_processor.dart';

class FakeAvatarImageProcessor implements AvatarImageProcessor {
  FakeAvatarImageProcessor({this.throwError});

  /// When set, `validate` throws this instead of resolving. Use an
  /// [AvatarImageValidationException] to simulate a rejected file, or any
  /// other exception to simulate an unexpected processing failure.
  Exception? throwError;

  final List<String> validatedPaths = [];

  @override
  Future<void> validate(String path) async {
    validatedPaths.add(path);
    if (throwError != null) throw throwError!;
  }
}
