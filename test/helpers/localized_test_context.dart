import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/localization/app_locale.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

/// Pumps a minimal [MaterialApp] with the app's real translation delegates
/// registered and [locale] active, then returns a [BuildContext] from
/// inside it — for unit-testing functions that need `context.t(...)`
/// (validators, status-label helpers, etc.) without pumping a full screen.
Future<BuildContext> pumpLocalizedContext(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocale.supportedLocales,
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return capturedContext;
}
