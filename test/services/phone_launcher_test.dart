// Unit tests for PhoneLauncher's tel: dialer launch flow. Uses a fake
// UrlLauncherClient so the real url_launcher plugin is never invoked.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/phone_launcher.dart';

import '../helpers/fake_url_launcher_client.dart';

void main() {
  group('PhoneLauncher.call', () {
    test(
      'returns unavailable and launches nothing for a null number',
      () async {
        final client = FakeUrlLauncherClient();
        final result = await PhoneLauncher(client: client).call(null);

        expect(result.outcome, PhoneLaunchOutcome.unavailable);
        expect(client.attemptedUris, isEmpty);
      },
    );

    test(
      'returns unavailable and launches nothing for an empty number',
      () async {
        final client = FakeUrlLauncherClient();
        final result = await PhoneLauncher(client: client).call('');

        expect(result.outcome, PhoneLaunchOutcome.unavailable);
        expect(client.attemptedUris, isEmpty);
      },
    );

    test(
      'returns unavailable and launches nothing for an unusable number',
      () async {
        final client = FakeUrlLauncherClient();
        final result = await PhoneLauncher(client: client).call('+');

        expect(result.outcome, PhoneLaunchOutcome.unavailable);
        expect(client.attemptedUris, isEmpty);
      },
    );

    test(
      'attempts a tel: URI preserving the leading + and country code',
      () async {
        final client = FakeUrlLauncherClient(telResult: true);
        await PhoneLauncher(client: client).call('+961 1 275 019');

        expect(client.attemptedUris, hasLength(1));
        expect(client.attemptedUris.single.toString(), 'tel:+9611275019');
      },
    );

    test('attempts a tel: URI for a local number without guessing a '
        'country code', () async {
      final client = FakeUrlLauncherClient(telResult: true);
      await PhoneLauncher(client: client).call('(01) 234 567');

      expect(client.attemptedUris.single.toString(), 'tel:01234567');
    });

    test('reports launched when the dialer opens successfully', () async {
      final client = FakeUrlLauncherClient(telResult: true);
      final result = await PhoneLauncher(
        client: client,
      ).call('+971-4-123-4567');

      expect(result.outcome, PhoneLaunchOutcome.launched);
      expect(result.normalizedNumber, '+97141234567');
      expect(result.succeeded, isTrue);
    });

    test(
      'reports failed without throwing when the launch returns false',
      () async {
        final client = FakeUrlLauncherClient(telResult: false);
        final result = await PhoneLauncher(
          client: client,
        ).call('+971 4 123 4567');

        expect(result.outcome, PhoneLaunchOutcome.failed);
        expect(result.succeeded, isFalse);
      },
    );

    test('reports failed without throwing when the launch throws', () async {
      final client = FakeUrlLauncherClient(
        telResult: Exception('dialer launch failed'),
      );
      final result = await PhoneLauncher(
        client: client,
      ).call('+971 4 123 4567');

      expect(result.outcome, PhoneLaunchOutcome.failed);
      expect(result.succeeded, isFalse);
    });
  });
}
