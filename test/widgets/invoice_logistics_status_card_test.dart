// Focused widget checks for InvoiceLogisticsStatusCard, independent of the
// full Invoice Details screen: empty-state safety, partial-data behavior
// (no placeholders for missing fields), the always-stacked full-width field
// boxes, and the status dot.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/invoice.dart';
import 'package:anc_fabrics/widgets/invoice_logistics_status_card.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  InvoiceLogisticsInfo? logistics, {
  double width = 400,
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
        // Matches how InvoiceDetailsScreen actually hosts this card: inside
        // a scrollable, so unbounded height is available and a long-status/
        // large-text-scale card can grow instead of overflowing.
        body: SingleChildScrollView(
          child: InvoiceLogisticsStatusCard(logistics: logistics),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Empty-state behavior', () {
    testWidgets('Renders nothing when logistics is null', (tester) async {
      await _pumpCard(tester, null);

      expect(find.text('Logistics'), findsNothing);
      expect(find.text('STATUS'), findsNothing);
      expect(find.text('EST. DELIVERY'), findsNothing);
      expect(
        find.byKey(const ValueKey('invoice-logistics-card')),
        findsNothing,
      );
    });

    testWidgets(
      'Renders nothing when statusLabel and estimatedDeliveryDate are both '
      'unset',
      (tester) async {
        await _pumpCard(tester, const InvoiceLogisticsInfo());

        expect(find.text('Logistics'), findsNothing);
        expect(find.text('STATUS'), findsNothing);
        expect(find.text('EST. DELIVERY'), findsNothing);
      },
    );

    testWidgets('Treats a whitespace-only status as absent', (tester) async {
      await _pumpCard(tester, const InvoiceLogisticsInfo(statusLabel: '   '));

      expect(find.text('Logistics'), findsNothing);
      expect(find.text('STATUS'), findsNothing);
    });
  });

  group('Outer card heading', () {
    testWidgets('Uses exactly "Logistics", not "Logistics Status"', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const InvoiceLogisticsInfo(statusLabel: 'In Production'),
      );

      expect(find.text('Logistics'), findsOneWidget);
      expect(find.text('Logistics Status'), findsNothing);
    });
  });

  group('Partial-data behavior', () {
    testWidgets(
      'Status-only data renders one full-width STATUS box and no EST. '
      'DELIVERY or placeholder',
      (tester) async {
        await _pumpCard(
          tester,
          const InvoiceLogisticsInfo(statusLabel: 'In Production'),
        );

        expect(find.text('Logistics'), findsOneWidget);
        expect(find.text('STATUS'), findsOneWidget);
        expect(find.text('In Production'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('invoice-logistics-status-box')),
          findsOneWidget,
        );
        expect(find.text('EST. DELIVERY'), findsNothing);
        expect(
          find.byKey(const ValueKey('invoice-logistics-delivery-box')),
          findsNothing,
        );
        expect(find.text('—'), findsNothing);
        expect(find.text('N/A'), findsNothing);
        expect(find.text('null'), findsNothing);
      },
    );

    testWidgets(
      'Date-only data renders one full-width EST. DELIVERY box and no '
      'STATUS or placeholder',
      (tester) async {
        await _pumpCard(
          tester,
          InvoiceLogisticsInfo(estimatedDeliveryDate: DateTime(2023, 10, 30)),
        );

        expect(find.text('Logistics'), findsOneWidget);
        expect(find.text('EST. DELIVERY'), findsOneWidget);
        expect(find.text('Oct 30, 2023'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('invoice-logistics-delivery-box')),
          findsOneWidget,
        );
        expect(find.text('STATUS'), findsNothing);
        expect(
          find.byKey(const ValueKey('invoice-logistics-status-box')),
          findsNothing,
        );
        expect(find.text('—'), findsNothing);
        expect(find.text('N/A'), findsNothing);
        expect(find.text('null'), findsNothing);
      },
    );

    testWidgets('Full data displays both fields using the supplied model '
        'values', (tester) async {
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

  group('Stacked field-box layout', () {
    testWidgets(
      'STATUS and EST. DELIVERY are separate, full-width, stacked boxes '
      '(not side by side) at a standard width',
      (tester) async {
        await _pumpCard(
          tester,
          InvoiceLogisticsInfo(
            statusLabel: 'In Production',
            estimatedDeliveryDate: DateTime(2023, 10, 30),
          ),
          width: 400,
        );

        final statusBox = tester.getRect(
          find.byKey(const ValueKey('invoice-logistics-status-box')),
        );
        final deliveryBox = tester.getRect(
          find.byKey(const ValueKey('invoice-logistics-delivery-box')),
        );

        // Stacked: EST. DELIVERY sits below STATUS, not beside it.
        expect(deliveryBox.top, greaterThanOrEqualTo(statusBox.bottom));
        // Both full width: same horizontal extent.
        expect(statusBox.left, deliveryBox.left);
        expect(statusBox.width, deliveryBox.width);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Fields remain stacked (not side by side) at a narrow width', (
      tester,
    ) async {
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

    testWidgets('A single field still renders as a full-width box', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const InvoiceLogisticsInfo(statusLabel: 'In Production'),
        width: 400,
      );

      final cardWidth = tester
          .getRect(find.byKey(const ValueKey('invoice-logistics-card')))
          .width;
      final statusBoxWidth = tester
          .getRect(find.byKey(const ValueKey('invoice-logistics-status-box')))
          .width;
      // Full width relative to the card's content area (card width minus
      // its own horizontal padding).
      expect(statusBoxWidth, greaterThan(cardWidth * 0.7));
    });
  });

  group('Status dot', () {
    testWidgets('Renders a small dot before the status text', (tester) async {
      await _pumpCard(
        tester,
        const InvoiceLogisticsInfo(statusLabel: 'In Production'),
      );

      expect(
        find.byKey(const ValueKey('invoice-logistics-status-dot')),
        findsOneWidget,
      );

      final dotX = tester
          .getTopLeft(
            find.byKey(const ValueKey('invoice-logistics-status-dot')),
          )
          .dx;
      final textX = tester.getTopLeft(find.text('In Production')).dx;
      expect(dotX, lessThan(textX));
    });

    testWidgets('No dot when there is no status', (tester) async {
      await _pumpCard(
        tester,
        InvoiceLogisticsInfo(estimatedDeliveryDate: DateTime(2023, 10, 30)),
      );

      expect(
        find.byKey(const ValueKey('invoice-logistics-status-dot')),
        findsNothing,
      );
    });
  });

  group('Responsive/overflow safety', () {
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
  });
}
