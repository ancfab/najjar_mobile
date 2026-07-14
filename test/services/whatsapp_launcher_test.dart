// Unit tests for WhatsAppLauncher's native-app-first, web-fallback launch
// flow. Uses a fake UrlLauncherClient so the real url_launcher plugin is
// never invoked.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/whatsapp_launcher.dart';

import '../helpers/fake_url_launcher_client.dart';

void main() {
  group('WhatsAppLauncher.open', () {
    test(
      'returns unavailable and launches nothing for a null number',
      () async {
        final client = FakeUrlLauncherClient();
        final result = await WhatsAppLauncher(client: client).open(null);

        expect(result.outcome, WhatsAppLaunchOutcome.unavailable);
        expect(client.attemptedUris, isEmpty);
      },
    );

    test(
      'returns unavailable and launches nothing for an empty number',
      () async {
        final client = FakeUrlLauncherClient();
        final result = await WhatsAppLauncher(client: client).open('');

        expect(result.outcome, WhatsAppLaunchOutcome.unavailable);
        expect(client.attemptedUris, isEmpty);
      },
    );

    test(
      'attempts the native URI with the normalized, digits-only number',
      () async {
        final client = FakeUrlLauncherClient(nativeResult: true);
        await WhatsAppLauncher(client: client).open('+971-50-123-4567');

        expect(client.attemptedUris, hasLength(1));
        expect(
          client.attemptedUris.single.toString(),
          'whatsapp://send?phone=971501234567',
        );
      },
    );

    test(
      'does not attempt the web fallback when the native launch succeeds',
      () async {
        final client = FakeUrlLauncherClient(nativeResult: true);
        final result = await WhatsAppLauncher(
          client: client,
        ).open('+971 50 123 4567');

        expect(result.outcome, WhatsAppLaunchOutcome.launchedNative);
        expect(result.normalizedNumber, '971501234567');
        expect(client.attemptedUris, hasLength(1));
      },
    );

    test(
      'attempts the web fallback when the native launch returns false',
      () async {
        final client = FakeUrlLauncherClient(
          nativeResult: false,
          webResult: true,
        );
        final result = await WhatsAppLauncher(
          client: client,
        ).open('+971 50 123 4567');

        expect(result.outcome, WhatsAppLaunchOutcome.launchedWeb);
        expect(client.attemptedUris, hasLength(2));
        expect(
          client.attemptedUris[1].toString(),
          'https://wa.me/971501234567',
        );
      },
    );

    test('attempts the web fallback when the native launch throws', () async {
      final client = FakeUrlLauncherClient(
        nativeResult: Exception('native launch failed'),
        webResult: true,
      );
      final result = await WhatsAppLauncher(
        client: client,
      ).open('+971 50 123 4567');

      expect(result.outcome, WhatsAppLaunchOutcome.launchedWeb);
      expect(client.attemptedUris, hasLength(2));
    });

    test('reports success when only the web fallback succeeds', () async {
      final client = FakeUrlLauncherClient(
        nativeResult: false,
        webResult: true,
      );
      final result = await WhatsAppLauncher(
        client: client,
      ).open('+961 3 123 456');

      expect(result.succeeded, isTrue);
    });

    test(
      'reports failure when both native and web launches return false',
      () async {
        final client = FakeUrlLauncherClient(
          nativeResult: false,
          webResult: false,
        );
        final result = await WhatsAppLauncher(
          client: client,
        ).open('+971 50 123 4567');

        expect(result.outcome, WhatsAppLaunchOutcome.failed);
        expect(result.succeeded, isFalse);
      },
    );

    test('reports failure without throwing when both native and web launches '
        'throw', () async {
      final client = FakeUrlLauncherClient(
        nativeResult: Exception('native failed'),
        webResult: Exception('web failed'),
      );
      final result = await WhatsAppLauncher(
        client: client,
      ).open('+971 50 123 4567');

      expect(result.outcome, WhatsAppLaunchOutcome.failed);
      expect(result.succeeded, isFalse);
    });
  });
}
