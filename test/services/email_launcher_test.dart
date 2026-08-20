// Unit tests for EmailLauncher's mailto: draft launch flow. Uses a fake
// UrlLauncherClient so the real url_launcher plugin is never invoked.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/services/email_launcher.dart';

import '../helpers/fake_url_launcher_client.dart';

void main() {
  group('EmailLauncher.send', () {
    test(
      'returns unavailable and launches nothing for a null recipient',
      () async {
        final client = FakeUrlLauncherClient();
        final result = await EmailLauncher(client: client).send(to: null);

        expect(result.outcome, EmailLaunchOutcome.unavailable);
        expect(client.attemptedUris, isEmpty);
      },
    );

    test(
      'returns unavailable and launches nothing for a blank recipient',
      () async {
        final client = FakeUrlLauncherClient();
        final result = await EmailLauncher(client: client).send(to: '   ');

        expect(result.outcome, EmailLaunchOutcome.unavailable);
        expect(client.attemptedUris, isEmpty);
      },
    );

    test('attempts a mailto: URI addressed to the trimmed recipient', () async {
      final client = FakeUrlLauncherClient(webResult: true);
      await EmailLauncher(client: client).send(to: '  info@najjar-lb.com  ');

      expect(client.attemptedUris, hasLength(1));
      final uri = client.attemptedUris.single;
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'info@najjar-lb.com');
    });

    test(
      'includes subject and body as query parameters when supplied',
      () async {
        final client = FakeUrlLauncherClient(webResult: true);
        await EmailLauncher(client: client).send(
          to: 'info@anc-syr.com',
          subject: 'Technical Support',
          body: 'Name: Jane Weaver\nEmail: jane@textile.co',
        );

        final uri = client.attemptedUris.single;
        expect(uri.queryParameters['subject'], 'Technical Support');
        expect(
          uri.queryParameters['body'],
          'Name: Jane Weaver\nEmail: jane@textile.co',
        );
      },
    );

    test('omits empty subject/body query parameters', () async {
      final client = FakeUrlLauncherClient(webResult: true);
      await EmailLauncher(client: client).send(to: 'info@anc-syr.com');

      final uri = client.attemptedUris.single;
      expect(uri.queryParameters.containsKey('subject'), isFalse);
      expect(uri.queryParameters.containsKey('body'), isFalse);
    });

    test('reports launched when the email app opens successfully', () async {
      final client = FakeUrlLauncherClient(webResult: true);
      final result = await EmailLauncher(
        client: client,
      ).send(to: 'accounting01@anc-uae.com');

      expect(result.outcome, EmailLaunchOutcome.launched);
      expect(result.succeeded, isTrue);
    });

    test(
      'reports failed without throwing when the launch returns false',
      () async {
        final client = FakeUrlLauncherClient(webResult: false);
        final result = await EmailLauncher(
          client: client,
        ).send(to: 'accounting01@anc-uae.com');

        expect(result.outcome, EmailLaunchOutcome.failed);
        expect(result.succeeded, isFalse);
      },
    );

    test('reports failed without throwing when the launch throws', () async {
      final client = FakeUrlLauncherClient(
        webResult: Exception('email client launch failed'),
      );
      final result = await EmailLauncher(
        client: client,
      ).send(to: 'accounting01@anc-uae.com');

      expect(result.outcome, EmailLaunchOutcome.failed);
      expect(result.succeeded, isFalse);
    });
  });
}
