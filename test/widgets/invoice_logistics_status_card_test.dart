// Focused widget checks for InvoiceLogisticsStatusCard, independent of the
// full Invoice Details screen: empty-state safety, partial-data behavior
// (no placeholders for missing fields), and the two-column/stacked
// responsive layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/invoice.dart';
import 'package:anc_fabrics/widgets/invoice_logistics_status_card.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  InvoiceLogisticsInfo? logistics, {
  double width = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: InvoiceLogisticsStatusCard(logistics: logistics),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Empty-state behavior', () {
    testWidgets('Renders nothing when logistics is null', (tester) async {
      await _pumpCard(tester, null);

      expect(find.text('Logistics Status'), findsNothing);
      expect(find.text('STATUS'), findsNothing);
      expect(find.text('EST. DELIVERY'), findsNothing);
    });

    testWidgets(
      'Renders nothing when statusLabel and estimatedDeliveryDate are both '
      'unset',
      (tester) async {
        await _pumpCard(tester, const InvoiceLogisticsInfo());

        expect(find.text('Logistics Status'), findsNothing);
        expect(find.text('STATUS'), findsNothing);
        expect(find.text('EST. DELIVERY'), findsNothing);
      },
    );

    testWidgets('Treats a whitespace-only status as absent', (tester) async {
      await _pumpCard(tester, const InvoiceLogisticsInfo(statusLabel: '   '));

      expect(find.text('Logistics Status'), findsNothing);
      expect(find.text('STATUS'), findsNothing);
    });
  });

  group('Partial-data behavior', () {
    testWidgets(
      'Status-only data displays STATUS but not EST. DELIVERY or a '
      'placeholder',
      (tester) async {
        await _pumpCard(
          tester,
          const InvoiceLogisticsInfo(statusLabel: 'In Production'),
        );

        expect(find.text('Logistics Status'), findsOneWidget);
        expect(find.text('STATUS'), findsOneWidget);
        expect(find.text('In Production'), findsOneWidget);
        expect(find.text('EST. DELIVERY'), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(find.text('N/A'), findsNothing);
        expect(find.text('null'), findsNothing);
      },
    );

    testWidgets(
      'Date-only data displays EST. DELIVERY but not STATUS or a '
      'placeholder',
      (tester) async {
        await _pumpCard(
          tester,
          InvoiceLogisticsInfo(estimatedDeliveryDate: DateTime(2023, 10, 30)),
        );

        expect(find.text('Logistics Status'), findsOneWidget);
        expect(find.text('EST. DELIVERY'), findsOneWidget);
        expect(find.text('Oct 30, 2023'), findsOneWidget);
        expect(find.text('STATUS'), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(find.text('N/A'), findsNothing);
        expect(find.text('null'), findsNothing);
      },
    );

    testWidgets('Full data displays both fields', (tester) async {
      await _pumpCard(
        tester,
        InvoiceLogisticsInfo(
          statusLabel: 'In Production',
          estimatedDeliveryDate: DateTime(2023, 10, 30),
        ),
      );

      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('In Production'), findsOneWidget);
      expect(find.text('EST. DELIVERY'), findsOneWidget);
      expect(find.text('Oct 30, 2023'), findsOneWidget);
    });
  });

  group('Responsive layout', () {
    testWidgets('Standard/wide width uses a two-column layout', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        InvoiceLogisticsInfo(
          statusLabel: 'In Production',
          estimatedDeliveryDate: DateTime(2023, 10, 30),
        ),
        width: 400,
      );

      final statusY = tester.getTopLeft(find.text('STATUS')).dy;
      final deliveryY = tester.getTopLeft(find.text('EST. DELIVERY')).dy;
      expect(statusY, deliveryY);

      final statusX = tester.getTopLeft(find.text('STATUS')).dx;
      final deliveryX = tester.getTopLeft(find.text('EST. DELIVERY')).dx;
      expect(deliveryX, greaterThan(statusX));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Narrow width stacks the fields vertically', (tester) async {
      await _pumpCard(
        tester,
        InvoiceLogisticsInfo(
          statusLabel: 'In Production',
          estimatedDeliveryDate: DateTime(2023, 10, 30),
        ),
        width: 220,
      );

      final statusY = tester.getTopLeft(find.text('STATUS')).dy;
      final deliveryY = tester.getTopLeft(find.text('EST. DELIVERY')).dy;
      expect(deliveryY, greaterThan(statusY));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Long status text wraps without overflow at a narrow width', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        InvoiceLogisticsInfo(
          statusLabel:
              'Awaiting Customs Clearance At The Regional Distribution '
              'Facility Before Final Handoff',
          estimatedDeliveryDate: DateTime(2023, 10, 30),
        ),
        width: 220,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Increased text scale does not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pumpCard(
        tester,
        InvoiceLogisticsInfo(
          statusLabel: 'In Production',
          estimatedDeliveryDate: DateTime(2023, 10, 30),
        ),
        width: 320,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Status-only data does not force a two-column layout', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const InvoiceLogisticsInfo(statusLabel: 'In Production'),
        width: 400,
      );

      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('EST. DELIVERY'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
