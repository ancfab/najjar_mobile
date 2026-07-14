// Widget checks for the Support screen: intro content, the region
// selector's initial/selected state, and that the WhatsApp/Email/Hotline
// actions respond safely without throwing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/support_regions_data.dart';
import 'package:anc_fabrics/models/support_region.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/whatsapp_launcher.dart';
import 'package:anc_fabrics/utils/phone_number.dart';
import 'package:anc_fabrics/widgets/support_action_card.dart';
import 'package:anc_fabrics/widgets/support_hours_card.dart';
import 'package:anc_fabrics/widgets/support_info_card.dart';
import 'package:anc_fabrics/widgets/support_region_selector.dart';

import 'helpers/fake_url_launcher_client.dart';

void main() {
  Future<void> pumpSupport(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('Displays the intro section, region pills, and all cards', (
    tester,
  ) async {
    await pumpSupport(tester);

    expect(find.text('SUPPORT CENTER'), findsOneWidget);
    expect(find.text('How can we help your business thrive?'), findsOneWidget);

    for (final region in ['UAE', 'Syria', 'Iraq', 'Oman', 'Lebanon']) {
      expect(find.text(region), findsOneWidget);
    }

    expect(find.byType(SupportActionCard), findsOneWidget);
    expect(find.text('Live Specialist Support'), findsOneWidget);
    expect(find.text('CHAT ON WHATSAPP'), findsOneWidget);
    expect(find.text('EMAIL SUPPORT'), findsOneWidget);

    expect(find.byType(SupportInfoCard), findsNWidgets(2));
    expect(find.text('CORPORATE OFFICE'), findsOneWidget);
    expect(find.text('DIRECT HOTLINE'), findsOneWidget);
    expect(find.byType(SupportHoursCard), findsOneWidget);
    expect(find.text('SUPPORT HOURS'), findsOneWidget);
  });

  testWidgets('UAE region pill is selected initially', (tester) async {
    await pumpSupport(tester);

    final selector = tester.widget<SupportRegionSelector>(
      find.byType(SupportRegionSelector),
    );
    expect(selector.selectedRegionId, kSupportRegions.first.id);
  });

  testWidgets('Selecting another region updates the selected state', (
    tester,
  ) async {
    await pumpSupport(tester);

    final lebanon = kSupportRegions.firstWhere(
      (region) => region.id == SupportRegionId.lebanon,
    );

    await tester.tap(find.text(lebanon.displayName));
    await tester.pumpAndSettle();

    final selector = tester.widget<SupportRegionSelector>(
      find.byType(SupportRegionSelector),
    );
    expect(selector.selectedRegionId, lebanon.id);
    expect(
      find.text(
        'Office details for ${lebanon.displayName} will be added soon.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Support hours for ${lebanon.displayName} will be confirmed soon.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Selecting multiple regions sequentially leaves no stale information '
    'from the previous region',
    (tester) async {
      await pumpSupport(tester);

      for (final region in kSupportRegions) {
        await tester.tap(find.text(region.displayName));
        await tester.pumpAndSettle();

        final selector = tester.widget<SupportRegionSelector>(
          find.byType(SupportRegionSelector),
        );
        expect(selector.selectedRegionId, region.id);
        expect(
          find.text(
            'Office details for ${region.displayName} will be added soon.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Support hours for ${region.displayName} will be confirmed '
            'soon.',
          ),
          findsOneWidget,
        );

        for (final other in kSupportRegions) {
          if (other.id == region.id) continue;
          expect(
            find.text(
              'Office details for ${other.displayName} will be added soon.',
            ),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Screen remains stable after repeated region changes', (
    tester,
  ) async {
    await pumpSupport(tester);

    for (var i = 0; i < 3; i++) {
      for (final region in kSupportRegions) {
        await tester.tap(find.text(region.displayName));
        await tester.pumpAndSettle();
      }
    }

    expect(find.byType(SupportScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WhatsApp button reflects the currently selected region', (
    tester,
  ) async {
    await pumpSupport(tester);

    final uae = kSupportRegions.first;
    await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
    await tester.pump();
    expect(
      find.text(
        'WhatsApp support is not available for ${uae.displayName} '
        'yet.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final lebanon = kSupportRegions.firstWhere(
      (region) => region.id == SupportRegionId.lebanon,
    );
    await tester.tap(find.text(lebanon.displayName));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
    // The previous SnackBar's hide animation (triggered by
    // hideCurrentSnackBar in _onChatOnWhatsApp) needs a moment to finish
    // before the new one is shown, well short of its own auto-dismiss
    // duration.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        'WhatsApp support is not available for '
        '${lebanon.displayName} yet.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'WhatsApp support is not available for ${uae.displayName} '
        'yet.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  group('WhatsApp launch flow', () {
    final testRegion = SupportRegionData(
      id: SupportRegionId.uae,
      displayName: 'Testland',
      whatsappNumber: '+971 50 123 4567',
    );

    Future<void> pumpSupportWithRegion(
      WidgetTester tester,
      SupportRegionData region,
      WhatsAppLauncher launcher,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SupportScreen(regions: [region], whatsAppLauncher: launcher),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Native launch success does not attempt the web fallback and shows '
      'no error',
      (tester) async {
        final client = FakeUrlLauncherClient(nativeResult: true);
        await pumpSupportWithRegion(
          tester,
          testRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        final expectedNumber = normalizeWhatsAppNumber(
          testRegion.whatsappNumber,
        );
        expect(client.attemptedUris, hasLength(1));
        expect(
          client.attemptedUris.single.toString(),
          'whatsapp://send?phone=$expectedNumber',
        );
        expect(find.textContaining("Couldn't open WhatsApp"), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Native launch returning false attempts the web fallback and shows '
      'no error when it succeeds',
      (tester) async {
        final client = FakeUrlLauncherClient(
          nativeResult: false,
          webResult: true,
        );
        await pumpSupportWithRegion(
          tester,
          testRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        final expectedNumber = normalizeWhatsAppNumber(
          testRegion.whatsappNumber,
        );
        expect(client.attemptedUris, hasLength(2));
        expect(
          client.attemptedUris[0].toString(),
          'whatsapp://send?phone=$expectedNumber',
        );
        expect(
          client.attemptedUris[1].toString(),
          'https://wa.me/$expectedNumber',
        );
        expect(find.textContaining("Couldn't open WhatsApp"), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Native launch throwing attempts the web fallback', (
      tester,
    ) async {
      final client = FakeUrlLauncherClient(
        nativeResult: Exception('native failed'),
        webResult: true,
      );
      await pumpSupportWithRegion(
        tester,
        testRegion,
        WhatsAppLauncher(client: client),
      );

      await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Both native and web launches failing shows a user-friendly error',
      (tester) async {
        final client = FakeUrlLauncherClient(
          nativeResult: false,
          webResult: false,
        );
        await pumpSupportWithRegion(
          tester,
          testRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        expect(
          find.text(
            "Couldn't open WhatsApp for ${testRegion.displayName}. Please "
            'try again later.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'A region with no whatsappNumber never calls the launcher and shows '
      'the unavailable message',
      (tester) async {
        final client = FakeUrlLauncherClient();
        const unavailableRegion = SupportRegionData(
          id: SupportRegionId.syria,
          displayName: 'NoNumberLand',
        );
        await pumpSupportWithRegion(
          tester,
          unavailableRegion,
          WhatsAppLauncher(client: client),
        );

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pump();

        expect(client.attemptedUris, isEmpty);
        expect(
          find.text(
            'WhatsApp support is not available for '
            '${unavailableRegion.displayName} yet.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Selecting another region before tapping uses the new region\'s '
      'number, not the previous region\'s',
      (tester) async {
        final client = FakeUrlLauncherClient(nativeResult: true);
        final regionA = SupportRegionData(
          id: SupportRegionId.uae,
          displayName: 'RegionA',
          whatsappNumber: '+971 50 123 4567',
        );
        final regionB = SupportRegionData(
          id: SupportRegionId.lebanon,
          displayName: 'RegionB',
          whatsappNumber: '+961 3 123 456',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SupportScreen(
              regions: [regionA, regionB],
              whatsAppLauncher: WhatsAppLauncher(client: client),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(regionB.displayName));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
        await tester.pumpAndSettle();

        expect(client.attemptedUris, hasLength(1));
        expect(
          client.attemptedUris.single.toString(),
          'whatsapp://send?phone='
          '${normalizeWhatsAppNumber(regionB.whatsappNumber)}',
        );
      },
    );

    testWidgets('Rapid repeated taps only trigger a single launch attempt', (
      tester,
    ) async {
      // A launch that resolves purely through microtasks (as the other
      // fakes in this suite do) would finish draining before a second
      // `tester.tap()` even returns, making the guard untestable. Holding
      // the native launch open on a Completer keeps it "in flight" so the
      // guard can be observed blocking the repeated taps.
      final inFlight = Completer<bool>();
      final client = _ControlledUrlLauncherClient(inFlight.future);
      await pumpSupportWithRegion(
        tester,
        testRegion,
        WhatsAppLauncher(client: client),
      );

      final button = find.byKey(const ValueKey('support-whatsapp-button'));
      await tester.tap(button);
      await tester.tap(button);
      await tester.tap(button);

      expect(client.attemptedUris, hasLength(1));

      inFlight.complete(true);
      await tester.pumpAndSettle();

      expect(client.attemptedUris, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Email button opens the Contact Us screen without throwing', (
    tester,
  ) async {
    await pumpSupport(tester);

    await tester.tap(find.byKey(const ValueKey('support-email-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ContactUsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Fake [UrlLauncherClient] whose native launch stays pending until the
/// caller completes [result], used to observe the launch-in-progress
/// guard while a launch attempt is still in flight.
class _ControlledUrlLauncherClient implements UrlLauncherClient {
  _ControlledUrlLauncherClient(this.result);

  final Future<bool> result;
  final List<Uri> attemptedUris = [];

  @override
  Future<bool> launch(Uri uri) {
    attemptedUris.add(uri);
    return result;
  }
}
