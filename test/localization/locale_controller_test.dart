// Unit tests for LocaleController: defaults to English, notifies listeners
// and persists on change, and restores a previously persisted locale on the
// next "launch" (a fresh controller instance calling restorePersisted,
// mirroring what main.dart does at real app startup).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/localization/app_locale.dart';
import 'package:anc_fabrics/services/locale_controller.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to English (the safe fallback locale)', () {
    final controller = LocaleController();
    expect(controller.appLocale, AppLocale.english);
    expect(controller.locale.languageCode, 'en');
  });

  test('setLocale updates the active locale and notifies listeners', () async {
    final controller = LocaleController();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.setLocale(AppLocale.arabic);

    expect(controller.appLocale, AppLocale.arabic);
    expect(notifyCount, 1);
  });

  test('setLocale with the already-active locale is a no-op', () async {
    final controller = LocaleController();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.setLocale(AppLocale.english);

    expect(notifyCount, 0);
  });

  test('setLocale persists the language code to SharedPreferences', () async {
    final controller = LocaleController();
    await controller.setLocale(AppLocale.french);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionStorageKeys.localeCode), 'fr');
  });

  test('a fresh controller restores a previously persisted locale, simulating '
      'app restart', () async {
    final first = LocaleController();
    await first.setLocale(AppLocale.arabic);

    // A brand-new instance, as main.dart constructs at real startup —
    // never reads from the first controller's in-memory state, only from
    // SharedPreferences.
    final second = LocaleController();
    expect(second.appLocale, AppLocale.english);

    await second.restorePersisted();

    expect(second.appLocale, AppLocale.arabic);
  });

  test('restorePersisted is a no-op when nothing was ever persisted', () async {
    final controller = LocaleController();
    await controller.restorePersisted();
    expect(controller.appLocale, AppLocale.english);
  });
}
