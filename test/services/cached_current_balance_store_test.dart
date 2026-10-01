import 'dart:convert';

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/cached_current_balance_store.dart';
import 'package:anc_fabrics/services/current_balance_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_session_store.dart';
import '../helpers/fake_secure_key_value_store.dart';

AuthSession _session({int userId = 7}) => AuthSession(
  token: 'token-$userId',
  userId: userId,
  username: 'user-$userId',
  phone: '+9611234567',
  country: 'LB',
  clientId: 'ANCNAJJAR',
  mustChangePassword: false,
);

void main() {
  late FakeSecureKeyValueStore secureStore;
  late FakeAuthSessionStore sessionStore;
  late SecureCachedCurrentBalanceStore store;

  setUp(() {
    secureStore = FakeSecureKeyValueStore();
    sessionStore = FakeAuthSessionStore()..seed(_session());
    store = SecureCachedCurrentBalanceStore(
      secureStore: secureStore,
      sessionStore: sessionStore,
    );
  });

  group('save/load round trip', () {
    test('Saved amount and currency come back unchanged', () async {
      await store.save(
        const CurrentBalanceAmount(amount: 15320.75, currencyCode: 'AED'),
      );

      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.amount.amount, 15320.75);
      expect(loaded.amount.currencyCode, 'AED');
      expect(loaded.cachedAt.isUtc, isTrue);
    });

    test('A null currency code stays null, never a guessed currency', () async {
      await store.save(
        const CurrentBalanceAmount(amount: 500, currencyCode: null),
      );

      final loaded = await store.load();

      expect(loaded!.amount.currencyCode, isNull);
      expect(loaded.amount.amount, 500);
    });

    test('A zero balance round trips as a real zero', () async {
      await store.save(
        const CurrentBalanceAmount(amount: 0, currencyCode: 'USD'),
      );

      final loaded = await store.load();

      expect(loaded!.amount.amount, 0);
      expect(loaded.amount.currencyCode, 'USD');
    });
  });

  group('account scoping', () {
    test('One account never reads another account entry', () async {
      await store.save(
        const CurrentBalanceAmount(amount: 999, currencyCode: 'USD'),
      );

      sessionStore.seed(_session(userId: 8));

      expect(await store.load(), isNull);
    });

    test('Each account keeps its own entry', () async {
      await store.save(
        const CurrentBalanceAmount(amount: 111, currencyCode: 'USD'),
      );
      sessionStore.seed(_session(userId: 8));
      await store.save(
        const CurrentBalanceAmount(amount: 222, currencyCode: 'AED'),
      );

      expect((await store.load())!.amount.amount, 222);
      sessionStore.seed(_session());
      expect((await store.load())!.amount.amount, 111);
    });
  });

  group('no usable session', () {
    test('Load resolves to null rather than an unscoped entry', () async {
      final empty = SecureCachedCurrentBalanceStore(
        secureStore: secureStore,
        sessionStore: FakeAuthSessionStore(),
      );

      expect(await empty.load(), isNull);
    });

    test('Save writes nothing at all', () async {
      final empty = SecureCachedCurrentBalanceStore(
        secureStore: secureStore,
        sessionStore: FakeAuthSessionStore(),
      );

      await empty.save(
        const CurrentBalanceAmount(amount: 1, currencyCode: 'USD'),
      );

      expect(
        secureStore.containsKey(
          SecureCachedCurrentBalanceStore.keyForTesting(7),
        ),
        isFalse,
      );
    });

    test('A throwing session read is treated as no session', () async {
      sessionStore.readError = StateError('secure storage unavailable');

      expect(await store.load(), isNull);
    });
  });

  group('unusable stored data', () {
    test('A storage read failure resolves to null instead of throwing', () async {
      await store.save(
        const CurrentBalanceAmount(amount: 1, currencyCode: 'USD'),
      );
      secureStore.readError = StateError('keychain unavailable');

      expect(await store.load(), isNull);
    });

    test('Malformed JSON is discarded, not repaired', () async {
      secureStore.seed(
        SecureCachedCurrentBalanceStore.keyForTesting(7),
        'not json at all',
      );

      expect(await store.load(), isNull);
      expect(
        secureStore.containsKey(
          SecureCachedCurrentBalanceStore.keyForTesting(7),
        ),
        isFalse,
      );
    });

    test('An envelope missing its amount is discarded', () async {
      secureStore.seed(
        SecureCachedCurrentBalanceStore.keyForTesting(7),
        jsonEncode({'currencyCode': 'USD', 'cachedAt': '2026-09-30T12:00:00Z'}),
      );

      expect(await store.load(), isNull);
    });

    test('An envelope with an unparseable timestamp is discarded', () async {
      secureStore.seed(
        SecureCachedCurrentBalanceStore.keyForTesting(7),
        jsonEncode({
          'amount': 10,
          'currencyCode': 'USD',
          'cachedAt': 'whenever',
        }),
      );

      expect(await store.load(), isNull);
    });
  });

  test('A write failure is swallowed, never escalated to the caller', () async {
    secureStore.writeError = StateError('keychain full');

    await expectLater(
      store.save(const CurrentBalanceAmount(amount: 5, currencyCode: 'USD')),
      completes,
    );
  });
}
