import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_locale.dart';

/// Reusable translation lookup for one loaded locale's JSON file.
///
/// Keys are dotted paths into the nested JSON object (e.g.
/// `'home.activeOrders'`). Every lookup falls back to the English bundle
/// (loaded once and cached) so a key missing from Arabic/French — or a
/// locale entirely missing from the device — never crashes the UI; it just
/// silently shows the English string instead.
class Translations {
  Translations._(this._locale, this._values);

  final AppLocale _locale;
  final Map<String, dynamic> _values;

  static final Map<AppLocale, Map<String, dynamic>> _cache = {};

  static Future<Translations> load(AppLocale locale) async {
    final values = await _loadValues(locale);
    if (!_cache.containsKey(AppLocale.fallback)) {
      await _loadValues(AppLocale.fallback);
    }
    return Translations._(locale, values);
  }

  static Future<Map<String, dynamic>> _loadValues(AppLocale locale) async {
    final cached = _cache[locale];
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(
      'assets/translation/${locale.assetName}.json',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _cache[locale] = decoded;
    return decoded;
  }

  /// Looks up [key] (a dot-separated path, e.g. `'common.save'`) in this
  /// locale's translations, falling back to English, and finally to [key]
  /// itself so an unresolved key is visible (not blank) instead of crashing.
  String t(String key, {Map<String, String>? params}) {
    final resolved =
        _lookup(_values, key) ??
        _lookup(_cache[AppLocale.fallback], key) ??
        key;
    if (params == null || params.isEmpty) return resolved;
    var result = resolved;
    params.forEach((name, value) {
      result = result.replaceAll('{$name}', value);
    });
    return result;
  }

  AppLocale get locale => _locale;

  static String? _lookup(Map<String, dynamic>? values, String key) {
    if (values == null) return null;
    dynamic current = values;
    for (final segment in key.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current is String ? current : null;
  }
}

/// Convenience accessor: `context.t('common.save')`.
extension TranslationsContext on BuildContext {
  /// The active locale's loaded [Translations], or `null` on the first
  /// frame(s) before [AppTranslationsDelegate]'s async asset load
  /// completes. Deliberately nullable rather than asserting/throwing: a
  /// `Localizations` ancestor resolves its delegates asynchronously even
  /// when the underlying asset load is fast, so any widget built before
  /// that resolves would otherwise crash instead of simply being rebuilt
  /// (via the normal `InheritedWidget` dependency) once it's ready.
  Translations? get translations =>
      Localizations.of<Translations>(this, Translations);

  /// Shorthand for `context.translations?.t(key, params: params)`, falling
  /// back to the raw [key] for the brief window before translations have
  /// loaded (see [translations]) instead of crashing.
  String t(String key, {Map<String, String>? params}) =>
      translations?.t(key, params: params) ?? key;
}
