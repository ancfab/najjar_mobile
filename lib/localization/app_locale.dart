import 'package:flutter/widgets.dart';

/// The three locales this app ships translations for. English is the safe
/// fallback used whenever a device/persisted locale isn't one of these, and
/// whenever a translation key is missing from another locale's JSON file.
enum AppLocale {
  english(Locale('en'), 'english', 'English'),
  arabic(Locale('ar'), 'arabic', 'العربية'),
  french(Locale('fr'), 'french', 'Français');

  const AppLocale(this.locale, this.assetName, this.nativeName);

  /// The [Locale] registered with [MaterialApp.supportedLocales].
  final Locale locale;

  /// File name (without extension) under `assets/translation/` holding this
  /// locale's strings, e.g. `assets/translation/english.json`.
  final String assetName;

  /// The language name as shown in the language selector, written in that
  /// language itself (so it's recognizable regardless of the app's current
  /// language).
  final String nativeName;

  static const AppLocale fallback = AppLocale.english;

  static List<Locale> get supportedLocales =>
      values.map((locale) => locale.locale).toList(growable: false);

  /// Resolves a persisted/device language code (e.g. `'ar'`) to the matching
  /// [AppLocale], or [fallback] when unrecognized.
  static AppLocale fromLanguageCode(String? languageCode) {
    for (final locale in values) {
      if (locale.locale.languageCode == languageCode) return locale;
    }
    return fallback;
  }
}
