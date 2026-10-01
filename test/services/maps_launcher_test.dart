import 'package:anc_fabrics/services/maps_launcher.dart';
import 'package:anc_fabrics/utils/phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_url_launcher_client.dart';

void main() {
  group('MapsLauncher', () {
    test('Builds one maps search from every nonblank part', () async {
      final client = FakeUrlLauncherClient(webResult: true);
      final result = await MapsLauncher(
        client: client,
      ).openLocation(['ANC Najjar Fabric', 'Industrial Area 18', 'Sharjah']);

      expect(result.outcome, MapsLaunchOutcome.launched);
      final uri = client.attemptedUris.single;
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
      expect(
        uri.queryParameters['query'],
        'ANC Najjar Fabric, Industrial Area 18, Sharjah',
      );
    });

    test('Drops null and blank parts rather than leaving empty gaps', () async {
      final client = FakeUrlLauncherClient(webResult: true);
      await MapsLauncher(
        client: client,
      ).openLocation([null, '   ', 'استراد دمشق', 'Aleppo']);

      expect(
        client.attemptedUris.single.queryParameters['query'],
        'استراد دمشق, Aleppo',
      );
    });

    test('Nothing to search attempts no launch at all', () async {
      final client = FakeUrlLauncherClient(webResult: true);
      final result = await MapsLauncher(
        client: client,
      ).openLocation([null, '  ']);

      expect(result.outcome, MapsLaunchOutcome.unavailable);
      expect(client.attemptedUris, isEmpty);
    });

    test('A refused launch reports failure instead of throwing', () async {
      final client = FakeUrlLauncherClient(webResult: false);
      final result = await MapsLauncher(client: client).openLocation(['Beirut']);

      expect(result.outcome, MapsLaunchOutcome.failed);
    });

    test('A throwing launch reports failure instead of propagating', () async {
      final client = FakeUrlLauncherClient(webResult: Exception('no handler'));
      final result = await MapsLauncher(client: client).openLocation(['Beirut']);

      expect(result.outcome, MapsLaunchOutcome.failed);
    });
  });

  group('normalizeWhatsAppNumberWithDialCode', () {
    test('A local number gains the region code, minus its trunk 0', () {
      expect(
        normalizeWhatsAppNumberWithDialCode('0989204480', '+963'),
        '963989204480',
      );
    });

    test('A local number without a trunk 0 keeps every digit', () {
      expect(
        normalizeWhatsAppNumberWithDialCode('989204480', '+963'),
        '963989204480',
      );
    });

    test('Display separators are stripped', () {
      expect(
        normalizeWhatsAppNumberWithDialCode('098 920 44-80', '+963'),
        '963989204480',
      );
    });

    test('An international number keeps its own code, ignoring the region', () {
      expect(
        normalizeWhatsAppNumberWithDialCode('+964 751 401 8777', '+963'),
        '9647514018777',
      );
    });

    test('A local number with no known region code resolves to null', () {
      expect(normalizeWhatsAppNumberWithDialCode('0989204480', null), isNull);
    });

    test('Empty and digitless input resolve to null', () {
      expect(normalizeWhatsAppNumberWithDialCode('', '+963'), isNull);
      expect(normalizeWhatsAppNumberWithDialCode('  ', '+963'), isNull);
      expect(normalizeWhatsAppNumberWithDialCode('0', '+963'), isNull);
    });
  });
}
