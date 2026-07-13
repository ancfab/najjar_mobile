// Widget checks for the Support screen: intro content, the region
// selector's initial/selected state, and that the WhatsApp/Email/Hotline
// actions respond safely without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(selector.selectedRegionId.name, 'uae');
  });

  testWidgets('Selecting another region updates the selected state', (
    tester,
  ) async {
    await pumpSupport(tester);

    await tester.tap(find.text('Lebanon'));
    await tester.pumpAndSettle();

    final selector = tester.widget<SupportRegionSelector>(
      find.byType(SupportRegionSelector),
    );
    expect(selector.selectedRegionId.name, 'lebanon');
    expect(
      find.text('Office details for Lebanon will be added soon.'),
      findsOneWidget,
    );
  });

  testWidgets('WhatsApp button shows a message without throwing', (
    tester,
  ) async {
    await pumpSupport(tester);

    await tester.tap(find.byKey(const ValueKey('support-whatsapp-button')));
    await tester.pump();
    expect(
      find.text('WhatsApp support is being set up for this region.'),
      findsOneWidget,
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
