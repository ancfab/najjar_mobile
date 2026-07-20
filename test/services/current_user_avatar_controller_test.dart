// Unit tests for CurrentUserAvatarController against the real
// shared_preferences plugin (mocked at the platform-channel level) and real
// dart:io File objects in a temp directory, so these verify actual
// persistence/restore/clear behavior rather than a fake standing in for it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'current_user_avatar_controller_test',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<File> writeAvatarFile(String name) async {
    final file = File('${tempDir.path}/$name');
    return file.writeAsBytes([1, 2, 3, 4]);
  }

  test('Has no avatar by default', () {
    final controller = CurrentUserAvatarController();

    expect(controller.avatarFile, isNull);
    expect(controller.imageProvider, isNull);
  });

  test('setAvatarPath sets the in-memory avatar and notifies listeners', () async {
    final controller = CurrentUserAvatarController();
    final file = await writeAvatarFile('avatar.jpg');
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.setAvatarPath(file.path);

    expect(controller.avatarFile?.path, file.path);
    expect(controller.imageProvider, isNotNull);
    expect(notified, 1);
  });

  test('setAvatarPath persists the path for restorePersisted to find', () async {
    final controller = CurrentUserAvatarController();
    final file = await writeAvatarFile('avatar.jpg');

    await controller.setAvatarPath(file.path);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionStorageKeys.localAvatarPath), file.path);
  });

  test(
    'restorePersisted restores a previously persisted avatar that still '
    'exists on disk',
    () async {
      final file = await writeAvatarFile('avatar.jpg');
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.localAvatarPath: file.path,
      });

      final controller = CurrentUserAvatarController();
      await controller.restorePersisted();

      expect(controller.avatarFile?.path, file.path);
    },
  );

  test(
    'restorePersisted does nothing when the persisted path no longer '
    'exists on disk (e.g. a stale temp-picker path)',
    () async {
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.localAvatarPath: '${tempDir.path}/missing.jpg',
      });

      final controller = CurrentUserAvatarController();
      await controller.restorePersisted();

      expect(controller.avatarFile, isNull);
    },
  );

  test('restorePersisted does nothing when no path was ever persisted', () async {
    final controller = CurrentUserAvatarController();

    await controller.restorePersisted();

    expect(controller.avatarFile, isNull);
  });

  test(
    'clear removes the in-memory avatar, deletes the underlying file, and '
    'notifies listeners',
    () async {
      final controller = CurrentUserAvatarController();
      final file = await writeAvatarFile('avatar.jpg');
      await controller.setAvatarPath(file.path);
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.clear();

      expect(controller.avatarFile, isNull);
      expect(controller.imageProvider, isNull);
      expect(await file.exists(), isFalse);
      expect(notified, 1);
    },
  );

  test(
    'clear is safe to call when no avatar was ever set',
    () async {
      final controller = CurrentUserAvatarController();

      await controller.clear();

      expect(controller.avatarFile, isNull);
    },
  );

  test(
    'A cleared avatar path is not restored by a later restorePersisted '
    "call, so the next signed-in user doesn't see the previous user's avatar",
    () async {
      final file = await writeAvatarFile('avatar.jpg');
      final controller = CurrentUserAvatarController();
      await controller.setAvatarPath(file.path);

      await controller.clear();

      final restored = CurrentUserAvatarController();
      await restored.restorePersisted();

      expect(restored.avatarFile, isNull);
    },
  );
}
