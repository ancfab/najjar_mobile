import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/app_locale.dart';
import 'session_storage_keys.dart';

/// Single shared source of truth for the app's active [AppLocale], mirroring
/// the [CurrentUserAvatarController] pattern: an app-wide `ChangeNotifier`
/// singleton, listened to by [MaterialApp] so changing the language rebuilds
/// the whole tree immediately, with the choice persisted via
/// SharedPreferences (not secure storage — the selected language isn't
/// sensitive) so it survives app restarts.
class LocaleController extends ChangeNotifier {
  LocaleController({AppLocale initial = AppLocale.fallback})
    : _locale = initial;

  AppLocale _locale;

  AppLocale get appLocale => _locale;

  Locale get locale => _locale.locale;

  /// Switches the active language and persists the choice. Safe to call
  /// with the already-active locale (no-op, no redundant notify).
  Future<void> setLocale(AppLocale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SessionStorageKeys.localeCode,
        locale.locale.languageCode,
      );
    } catch (error) {
      // The in-memory locale is already switched and visible; only the
      // cross-restart persistence step failed.
      debugPrint('Failed to persist locale choice: $error');
    }
  }

  /// Restores a previously persisted locale (if any) so the app opens in
  /// the user's last chosen language instead of always the fallback. Safe
  /// to call multiple times; does nothing if nothing was persisted.
  Future<void> restorePersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(SessionStorageKeys.localeCode);
      if (code == null) return;
      final restored = AppLocale.fromLanguageCode(code);
      if (restored != _locale) {
        _locale = restored;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Failed to restore persisted locale: $error');
    }
  }
}

/// App-wide singleton, used as the default [LocaleController] by
/// [MaterialApp]. Widgets/tests that need an isolated instance can still
/// construct their own [LocaleController] directly rather than sharing this
/// mutable singleton.
final LocaleController localeController = LocaleController();
