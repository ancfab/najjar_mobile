// Static checks on the translation JSON files themselves: valid JSON, and
// the English/Arabic/French files declare exactly the same set of keys with
// no missing or empty values. These are pure data checks — no widget
// pumping needed — so a translator adding/renaming a key in one file but
// forgetting the others fails fast here instead of surfacing as a runtime
// fallback-to-English somewhere in the app.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadJson(String assetName) {
  final file = File('assets/translation/$assetName.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Flattens a nested translation map into dotted leaf keys, e.g.
/// `{"common": {"save": "Save"}}` -> `{"common.save"}`.
Set<String> _flattenKeys(Map<String, dynamic> map, [String prefix = '']) {
  final keys = <String>{};
  map.forEach((key, value) {
    final fullKey = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      keys.addAll(_flattenKeys(value, fullKey));
    } else {
      keys.add(fullKey);
    }
  });
  return keys;
}

/// Every non-Map leaf value's dotted key mapped to whether it's a
/// non-empty String.
Map<String, dynamic> _flattenValues(
  Map<String, dynamic> map, [
  String prefix = '',
]) {
  final values = <String, dynamic>{};
  map.forEach((key, value) {
    final fullKey = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      values.addAll(_flattenValues(value, fullKey));
    } else {
      values[fullKey] = value;
    }
  });
  return values;
}

void main() {
  late Map<String, dynamic> english;
  late Map<String, dynamic> arabic;
  late Map<String, dynamic> french;

  setUpAll(() {
    english = _loadJson('english');
    arabic = _loadJson('arabic');
    french = _loadJson('french');
  });

  test('all three translation files are valid, non-empty JSON objects', () {
    expect(english, isNotEmpty);
    expect(arabic, isNotEmpty);
    expect(french, isNotEmpty);
  });

  test('Arabic declares exactly the same keys as English', () {
    final englishKeys = _flattenKeys(english);
    final arabicKeys = _flattenKeys(arabic);

    expect(
      arabicKeys.difference(englishKeys),
      isEmpty,
      reason: 'arabic.json has keys not present in english.json',
    );
    expect(
      englishKeys.difference(arabicKeys),
      isEmpty,
      reason: 'arabic.json is missing keys present in english.json',
    );
  });

  test('French declares exactly the same keys as English', () {
    final englishKeys = _flattenKeys(english);
    final frenchKeys = _flattenKeys(french);

    expect(
      frenchKeys.difference(englishKeys),
      isEmpty,
      reason: 'french.json has keys not present in english.json',
    );
    expect(
      englishKeys.difference(frenchKeys),
      isEmpty,
      reason: 'french.json is missing keys present in english.json',
    );
  });

  for (final entry in {'english': null, 'arabic': null, 'french': null}.keys) {
    test('$entry.json has no missing or empty values', () {
      final map = switch (entry) {
        'english' => english,
        'arabic' => arabic,
        'french' => french,
        _ => throw StateError('unreachable'),
      };
      final values = _flattenValues(map);
      final badEntries = <String>[];
      values.forEach((key, value) {
        if (value is! String || value.trim().isEmpty) {
          badEntries.add(key);
        }
      });
      expect(
        badEntries,
        isEmpty,
        reason: 'Missing/empty translation values: $badEntries',
      );
    });
  }
}
