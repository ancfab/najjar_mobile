// Widget checks for HomeHeader's avatar: initials/person-icon fallback when
// no shared avatar is set, and reflecting a shared CurrentUserAvatarController
// image once one is set — the same shared state EditProfileScreen writes to.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/widgets/home_header.dart';

void main() {
  testWidgets('Shows the person-icon fallback when no avatar is set', (
    tester,
  ) async {
    final avatarController = CurrentUserAvatarController();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeHeader(
          userName: 'Alex Sterling',
          avatarController: avatarController,
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
          home: HomeHeader(
            userName: 'Alex Sterling',
            avatarController: avatarController,
          ),
        ),
      );

      final tempFile = await File(
        '${Directory.systemTemp.path}/home_header_avatar_test.jpg',
      ).writeAsBytes([0, 1, 2, 3]);
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
