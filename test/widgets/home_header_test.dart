// Widget checks for HomeHeader's avatar: initials/person-icon fallback when
// no shared avatar is set, and reflecting a shared CurrentUserAvatarController
// image once one is set — the same shared state EditProfileScreen writes to.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/widgets/home_header.dart';

import '../helpers/valid_avatar_image.dart';

void main() {
  setUp(() {
    // CurrentUserAvatarController.setAvatarPath persists the path via
    // SharedPreferences; without a mock in place, the real plugin's
    // getInstance() call never resolves in a widget test (no platform to
    // answer it), hanging avatar-setting tests until they time out instead
    // of failing fast.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Shows the person-icon fallback when no avatar is set', (
    tester,
  ) async {
    final avatarController = CurrentUserAvatarController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeader(
            userName: 'Alex Sterling',
            avatarController: avatarController,
          ),
        ),
      ),
    );

    final circleAvatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(circleAvatar.backgroundImage, isNull);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets(
    'Reflects the shared avatar image once CurrentUserAvatarController is '
    'updated',
    (tester) async {
      final avatarController = CurrentUserAvatarController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeHeader(
              userName: 'Alex Sterling',
              avatarController: avatarController,
            ),
          ),
        ),
      );

      late File tempFile;
      await tester.runAsync(() async {
        tempFile = await writeAndPrecacheAvatarFile(
          path: '${Directory.systemTemp.path}/home_header_avatar_test.png',
          bytes: validAvatarPngBytes,
          context: tester.element(find.byType(MaterialApp)),
        );
      });
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      await avatarController.setAvatarPath(tempFile.path);
      await tester.pumpAndSettle();

      final circleAvatar = tester.widget<CircleAvatar>(
        find.byType(CircleAvatar),
      );
      expect(circleAvatar.backgroundImage, isNotNull);
      expect(find.byIcon(Icons.person), findsNothing);
    },
  );
}
