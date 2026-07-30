import 'package:flutter/widgets.dart';

import 'app_locale.dart';
import 'translations.dart';

/// Loads [Translations] for whichever of [AppLocale.supportedLocales]
/// [MaterialApp] resolves as the active locale.
class AppTranslationsDelegate extends LocalizationsDelegate<Translations> {
  const AppTranslationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocale.values.any((l) => l.locale.languageCode == locale.languageCode);

  @override
  Future<Translations> load(Locale locale) =>
      Translations.load(AppLocale.fromLanguageCode(locale.languageCode));

  @override
  bool shouldReload(AppTranslationsDelegate old) => false;
}
