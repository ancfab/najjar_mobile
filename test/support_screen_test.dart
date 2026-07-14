// Widget checks for the Support screen: intro content, the region
// selector's initial/selected state, and that the WhatsApp/Email/Hotline
// actions respond safely without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/support_regions_data.dart';
import 'package:anc_fabrics/models/support_region.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/widgets/support_action_card.dart';
import 'package:anc_fabrics/widgets/support_hours_card.dart';
import 'package:anc_fabrics/widgets/support_info_card.dart';
import 'package:anc_fabrics/widgets/support_region_selector.dart';

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
      find.text('WhatsApp support for ${uae.displayName} is being set up.'),
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
      find.text('WhatsApp support for ${lebanon.displayName} is being set up.'),
      findsOneWidget,
    );
    expect(
      find.text('WhatsApp support for ${uae.displayName} is being set up.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
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
