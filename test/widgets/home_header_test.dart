// Widget checks for HomeHeader's avatar: initials/person-icon fallback when
// no shared avatar is set, and reflecting a shared CurrentUserAvatarController
// image once one is set — the same shared state EditProfileScreen writes to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/widgets/home_header.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Shows the person-icon fallback when no avatar is set', (
    tester,
  ) async {
    final avatarController = CurrentUserAvatarController();
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: HomeHeader(
            userName: 'Alex Sterling',
            avatarController: avatarController,
          ),
        ),
      ),
    );
    await tester.pump();

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
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: HomeHeader(
              userName: 'Alex Sterling',
              avatarController: avatarController,
            ),
          ),
        ),
      );
      await tester.pump();

      // A single pump (never pumpAndSettle) — the controller now holds a
      // network URL, and this only asserts the ImageProvider reference was
      // wired through the widget tree, not that a real fetch completed.
      // Loopback with nothing listening refuses the connection almost
      // instantly (no DNS lookup, no real round trip), unlike a real
      // internet host, which can resolve its async failure late enough to
      // be misattributed to whichever test runs next.
      avatarController.setAvatarUrl('http://127.0.0.1:9/avatars/7.jpg');
      await tester.pump();

      final circleAvatar = tester.widget<CircleAvatar>(
        find.byType(CircleAvatar),
      );
      expect(circleAvatar.backgroundImage, isNotNull);
      expect(find.byIcon(Icons.person), findsNothing);
    },
  );

  testWidgets(
    'Logo, language, and settings icons form a compact group with equal '
    'fixed gaps and no expanding spacer between them',
    (tester) async {
      final avatarController = CurrentUserAvatarController();
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: HomeHeader(
              userName: 'Alex Sterling',
              avatarController: avatarController,
            ),
          ),
        ),
      );
      await tester.pump();

      final logo = find.byKey(const ValueKey('home-header-logo'));
      final language = find.byKey(
        const ValueKey('home-header-language-button'),
      );
      final settings = find.byKey(
        const ValueKey('home-header-settings-button'),
      );

      // Logo is sized 34-36px tall (a modest bump from the prior 34px) and
      // keeps its aspect ratio (no explicit width forced on it).
      final logoSize = tester.getSize(logo);
      expect(logoSize.height, inInclusiveRange(34, 36));

      final logoRight = tester.getTopRight(logo).dx;
      final languageLeft = tester.getTopLeft(language).dx;
      final languageRight = tester.getTopRight(language).dx;
      final settingsLeft = tester.getTopLeft(settings).dx;

      final logoToLanguageGap = languageLeft - logoRight;
      final languageToSettingsGap = settingsLeft - languageRight;

      expect(logoToLanguageGap, closeTo(languageToSettingsGap, 0.5));
    },
  );

  testWidgets('Right-side action group does not overflow on a narrow phone '
      'width', (tester) async {
    final avatarController = CurrentUserAvatarController();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: HomeHeader(
            userName: 'Alex Sterling Longer Name For Testing',
            avatarController: avatarController,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('home-header-settings-button')),
      findsOneWidget,
    );
  });
}
