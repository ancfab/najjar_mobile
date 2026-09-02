// Unit tests for SecureLocalCustomerProfileStore against a fake in-memory
// SecureKeyValueStore — never real iOS Keychain / Android Keystore. Covers
// save/load round-trips, per-userId account isolation, clearing, and
// malformed/unreadable stored data failing safely instead of throwing.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/local_customer_profile.dart';
import 'package:anc_fabrics/services/local_customer_profile_store.dart';

import '../helpers/fake_secure_key_value_store.dart';

void main() {
  late FakeSecureKeyValueStore secureStore;
  late SecureLocalCustomerProfileStore store;

  setUp(() {
    secureStore = FakeSecureKeyValueStore();
    store = SecureLocalCustomerProfileStore(secureStore: secureStore);
  });

  const profileA = LocalCustomerProfile(
    fullName: 'Alexander Mitchell',
    email: 'alex.mitchell@example.com',
    company: 'Vanguard Global Logistics',
    businessAddress: '450 Fashion Ave, Suite 1205, New York, NY 10123',
  );

  const profileB = LocalCustomerProfile(
    fullName: 'Priya Natarajan',
    email: 'priya.n@example.com',
    company: 'Coastal Textiles LLC',
    businessAddress: '12 Harbor Road, Muscat',
  );

  test('load returns null when nothing has been saved yet', () async {
    expect(await store.load(7), isNull);
  });

  test('save then load round-trips the same profile', () async {
    await store.save(7, profileA);

    expect(await store.load(7), profileA);
  });

  test('two different userIds do not share profile data', () async {
    await store.save(7, profileA);
    await store.save(9, profileB);

    expect(await store.load(7), profileA);
    expect(await store.load(9), profileB);
  });

  test(
    'saving a new profile for the same userId overwrites the previous one',
    () async {
      await store.save(7, profileA);
      await store.save(7, profileB);

      expect(await store.load(7), profileB);
    },
  );

  test('clearing one userId leaves other userIds untouched', () async {
    await store.save(7, profileA);
    await store.save(9, profileB);

    await store.clear(7);

    expect(await store.load(7), isNull);
    expect(await store.load(9), profileB);
  });

  test('clear is safe to call when nothing was ever saved', () async {
    await expectLater(store.clear(7), completes);
  });

  test(
    'malformed (non-JSON) stored data resolves to null instead of throwing',
    () async {
      secureStore.seed(
        SecureLocalCustomerProfileStore.keyForTesting(7),
        'not json at all',
      );

      expect(await store.load(7), isNull);
    },
  );

  test('a stored JSON array (not an object) resolves to null instead of '
      'throwing', () async {
    secureStore.seed(
      SecureLocalCustomerProfileStore.keyForTesting(7),
      jsonEncode([1, 2, 3]),
    );

    expect(await store.load(7), isNull);
  });

  test('an empty stored string resolves to null instead of throwing', () async {
    secureStore.seed(SecureLocalCustomerProfileStore.keyForTesting(7), '');

    expect(await store.load(7), isNull);
  });

  test(
    'a secure-storage read failure resolves to null instead of throwing',
    () async {
      secureStore.readError = Exception('keystore unavailable');

      expect(await store.load(7), isNull);
    },
  );

  test('each userId is namespaced under its own storage key', () async {
    await store.save(7, profileA);

    expect(
      secureStore.containsKey(SecureLocalCustomerProfileStore.keyForTesting(7)),
      isTrue,
    );
    expect(
      secureStore.containsKey(SecureLocalCustomerProfileStore.keyForTesting(9)),
      isFalse,
    );
  });
}
