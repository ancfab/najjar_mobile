// Unit tests for SharedPreferencesSessionService against the real
// shared_preferences plugin (mocked at the platform-channel level, which is
// what SharedPreferences.setMockInitialValues does), so these verify the
// actual storage read/write/clear behavior logout depends on — not just a
// fake standing in for it.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const service = SharedPreferencesSessionService();

  test(
    'isLoggedIn defaults to false when no session was ever started',
    () async {
      expect(await service.isLoggedIn(), isFalse);
    },
  );

  test('startSession marks the session as active', () async {
    await service.startSession();
    expect(await service.isLoggedIn(), isTrue);
  });

  test('endSession clears the session and reports success', () async {
    await service.startSession();
    expect(await service.isLoggedIn(), isTrue);

    final result = await service.endSession();

    expect(result.succeeded, isTrue);
    expect(await service.isLoggedIn(), isFalse);
  });

  test('endSession removes every known session storage key', () async {
    await service.startSession();

    await service.endSession();

    final prefs = await SharedPreferences.getInstance();
    for (final key in SessionStorageKeys.all) {
      expect(prefs.containsKey(key), isFalse);
    }
  });

  test('endSession does not touch unrelated preference keys', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'language': 'en',
      'has_seen_onboarding': true,
    });
    await service.startSession();

    await service.endSession();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getString('language'), 'en');
    expect(prefs.getBool('has_seen_onboarding'), isTrue);
  });

  test('endSession is safe to call when no session was ever started', () async {
    final result = await service.endSession();

    expect(result.succeeded, isTrue);
    expect(await service.isLoggedIn(), isFalse);
  });
}
