// Focused widget checks for the reusable PaymentTimeline component,
// independent of the full Invoice Details screen: heading/event rendering,
// event order, marker/connector counts, empty-state safety, and long-title
// wrapping on a narrow viewport.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/invoice.dart';
import 'package:anc_fabrics/widgets/payment_timeline.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

final _events = [
  InvoiceTimelineEvent(
    title: 'Payment Received',
    occurredAt: DateTime(2023, 10, 16, 9, 12),
  ),
  InvoiceTimelineEvent(
    title: 'Invoice Sent',
    occurredAt: DateTime(2023, 10, 14, 14, 45),
  ),
  InvoiceTimelineEvent(
    title: 'Invoice Generated',
    occurredAt: DateTime(2023, 10, 14, 13, 20),
  ),
];

Future<void> _pumpTimeline(
  WidgetTester tester,
  List<InvoiceTimelineEvent> events, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(child: PaymentTimeline(events: events)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Renders the heading and all events with their timestamps', (
    tester,
  ) async {
    await _pumpTimeline(tester, _events);

    expect(find.text('Payment Timeline'), findsOneWidget);
    expect(find.text('Payment Received'), findsOneWidget);
    expect(find.text('Oct 16, 2023 - 09:12 AM'), findsOneWidget);
    expect(find.text('Invoice Sent'), findsOneWidget);
    expect(find.text('Oct 14, 2023 - 02:45 PM'), findsOneWidget);
    expect(find.text('Invoice Generated'), findsOneWidget);
    expect(find.text('Oct 14, 2023 - 01:20 PM'), findsOneWidget);
  });

  testWidgets('Renders events in the order supplied', (tester) async {
    await _pumpTimeline(tester, _events);

    final firstY = tester.getTopLeft(find.text('Payment Received')).dy;
    final secondY = tester.getTopLeft(find.text('Invoice Sent')).dy;
    final thirdY = tester.getTopLeft(find.text('Invoice Generated')).dy;

    expect(firstY, lessThan(secondY));
    expect(secondY, lessThan(thirdY));
  });

  testWidgets(
    'Renders one checkmark per event and connectors only between events',
    (tester) async {
      await _pumpTimeline(tester, _events);

      expect(find.byIcon(Icons.check), findsNWidgets(3));
      expect(
        find.byKey(const ValueKey('payment-timeline-marker')),
        findsNWidgets(3),
      );
      expect(
        find.byKey(const ValueKey('payment-timeline-connector')),
        findsNWidgets(2),
      );
    },
  );

  testWidgets('Renders nothing for an empty event list', (tester) async {
    await _pumpTimeline(tester, const []);

    expect(find.text('Payment Timeline'), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A long event title wraps without overflow on a narrow width', (
    tester,
  ) async {
    await _pumpTimeline(tester, [
      InvoiceTimelineEvent(
        title:
            'This is a deliberately very long Payment Timeline event title '
            'used to verify that it wraps naturally instead of overflowing '
            'the available width',
        occurredAt: DateTime(2023, 10, 16, 9, 12),
      ),
    ], width: 300);

    expect(find.textContaining('deliberately very long'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
