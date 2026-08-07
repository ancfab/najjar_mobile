// Unit tests for CurrentUserAvatarController: URL-based avatar state,
// image-cache eviction on replacement, and clear().

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/current_user_avatar_controller.dart';

import '../helpers/valid_avatar_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Has no avatar by default', () {
    final controller = CurrentUserAvatarController();

    expect(controller.avatarUrl, isNull);
    expect(controller.imageProvider, isNull);
  });

  test('setAvatarUrl sets the in-memory avatar and notifies listeners', () {
    final controller = CurrentUserAvatarController();
    var notified = 0;
    controller.addListener(() => notified++);

    controller.setAvatarUrl('https://cdn.example.com/avatars/7.jpg');

    expect(controller.avatarUrl, 'https://cdn.example.com/avatars/7.jpg');
    expect(controller.imageProvider, isNotNull);
    expect(controller.imageProvider, isA<NetworkImage>());
    expect(notified, 1);
  });

  test('setAvatarUrl(null) clears the in-memory avatar', () {
    final controller = CurrentUserAvatarController();
    controller.setAvatarUrl('https://cdn.example.com/avatars/7.jpg');

    controller.setAvatarUrl(null);

    expect(controller.avatarUrl, isNull);
    expect(controller.imageProvider, isNull);
  });

  testWidgets(
    'setAvatarUrl evicts the previous URL from the image cache before '
    'replacing it',
    (tester) async {
      const previousUrl = 'https://cdn.example.com/avatars/stale.jpg';
      final controller = CurrentUserAvatarController();
      controller.setAvatarUrl(previousUrl);

      // Seeds the cache as if the stale image had actually been resolved
      // once, so eviction has something real to remove. Decoding real
      // bytes (off the fake-async clock, via runAsync — see
      // valid_avatar_image.dart's doc comment) rather than a stub, since
      // ImageInfo requires a genuine ui.Image.
      final key = NetworkImage(previousUrl);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          Uint8List.fromList(validAvatarPngBytes),
        );
        final frame = await codec.getNextFrame();
        PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(
            Future<ImageInfo>.value(ImageInfo(image: frame.image, scale: 1.0)),
          ),
        );
      });
      expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);

      controller.setAvatarUrl('https://cdn.example.com/avatars/fresh.jpg');

      expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    },
  );

  test('clear removes the in-memory avatar and notifies listeners', () {
    final controller = CurrentUserAvatarController();
    controller.setAvatarUrl('https://cdn.example.com/avatars/7.jpg');
    var notified = 0;
    controller.addListener(() => notified++);

    controller.clear();

    expect(controller.avatarUrl, isNull);
    expect(controller.imageProvider, isNull);
    expect(notified, 1);
  });

  test('clear is safe to call when no avatar was ever set', () {
    final controller = CurrentUserAvatarController();

    controller.clear();

    expect(controller.avatarUrl, isNull);
  });
}
