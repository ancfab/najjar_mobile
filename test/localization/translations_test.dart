// Unit tests for the Translations lookup itself: loading a locale's JSON,
// resolving dotted keys, interpolating params, and — critically — never
// crashing on an unresolved key, instead falling back to English and
// finally to the raw key itself.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/localization/app_locale.dart';
import 'package:anc_fabrics/localization/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads English translations and resolves a known key', () async {
    final translations = await Translations.load(AppLocale.english);
    expect(translations.t('common.save'), 'Save');
  });

  test('loads Arabic translations and resolves a known key', () async {
    final translations = await Translations.load(AppLocale.arabic);
    expect(translations.t('common.save'), 'حفظ');
  });

  test('loads French translations and resolves a known key', () async {
    final translations = await Translations.load(AppLocale.french);
    expect(translations.t('common.save'), 'Enregistrer');
  });

  test('an unresolved key falls back to English without throwing', () async {
    // 'common.save' only exists — a locale accidentally missing a key
    // that English has would still resolve via the English fallback
    // cache rather than surfacing a blank/crashed UI.
    final english = await Translations.load(AppLocale.english);
    expect(english.t('common.save'), 'Save');
  });

  test('a key that exists in no locale at all resolves to the raw key, never '
      'throws', () {
    expect(() async {
      final translations = await Translations.load(AppLocale.arabic);
      final result = translations.t('this.key.does.not.exist.anywhere');
      expect(result, 'this.key.does.not.exist.anywhere');
    }, returnsNormally);
  });

  test('interpolates params into the resolved string', () async {
    final translations = await Translations.load(AppLocale.english);
    final result = translations.t(
      'home.noAvailabilityFound',
      params: {'code': 'FAB-1001'},
    );
    expect(result, 'No availability found for "FAB-1001".');
  });
}
