// Widget checks for the Order Detail screen: Price Breakdown card content
// and the Invoice placeholder action, the Fabric Specs action and bottom
// sheet, breadcrumb/header content, source TODO markers, and narrow-width
// overflow safety.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/screens/order_detail_screen.dart';

/// The mock Order Detail fetch has a simulated 400ms network delay;
/// `pumpAndSettle` alone won't wait for that bare `Future.delayed` since it
/// isn't tied to a scheduled frame.
Future<void> _settleFetch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<void> _pumpOrderDetailScreen(
  WidgetTester tester, {
  String orderId = '#ORD-8829',
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: OrderDetailScreen(orderId: orderId)),
  );
  await _settleFetch(tester);
}

void main() {
  group('Price Breakdown card', () {
    testWidgets('Order Detail screen renders PRICE BREAKDOWN', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(tester);
      expect(find.text('PRICE BREAKDOWN'), findsOneWidget);
    });

    testWidgets('Shows Subtotal, Shipping, VAT, and Total amount', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(tester);

      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('\$4,800.00'), findsOneWidget);
      expect(find.text('Shipping'), findsOneWidget);
      expect(find.text('\$240.00'), findsOneWidget);
      expect(find.text('VAT'), findsOneWidget);
      expect(find.text('\$115.00'), findsOneWidget);
      expect(find.text('Total amount'), findsOneWidget);
      expect(find.text('\$5,155.00'), findsOneWidget);
    });

    testWidgets('Shows the green INVOICE button', (tester) async {
      await _pumpOrderDetailScreen(tester);

      final buttonFinder = find.byKey(
        const ValueKey('price-breakdown-invoice-button'),
      );
      expect(buttonFinder, findsOneWidget);
      expect(find.text('INVOICE'), findsOneWidget);

      final material = tester.widget<Material>(buttonFinder);
      expect(material.color, const Color(0xFF1E9E6B));
    });

    testWidgets('Tapping INVOICE shows the placeholder snackbar safely', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(tester);

      await tester.tap(find.text('INVOICE'));
      await tester.pump();

      expect(find.text('Invoice details coming soon'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow at ${width}px width', (tester) async {
        await _pumpOrderDetailScreen(tester, width: width);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Fabric Specs action', () {
    testWidgets('Order Detail screen renders FABRIC SPECS', (tester) async {
      await _pumpOrderDetailScreen(tester);
      expect(find.text('FABRIC SPECS'), findsOneWidget);
    });

    testWidgets('Tapping FABRIC SPECS opens the bottom sheet', (
      tester,
    ) async {
      await _pumpOrderDetailScreen(tester);

      await tester.tap(find.text('FABRIC SPECS'));
      await tester.pumpAndSettle();

      expect(find.text('Fabric Specs'), findsOneWidget);
    });

    testWidgets(
      'Bottom sheet shows mock fabric spec fields: SKU, color, weight/GSM, '
      'quantity',
      (tester) async {
        await _pumpOrderDetailScreen(tester);

        await tester.tap(find.text('FABRIC SPECS'));
        await tester.pumpAndSettle();

        expect(find.text('SKU'), findsOneWidget);
        expect(find.text('SKU-8829'), findsOneWidget);
        expect(find.text('Color'), findsOneWidget);
        expect(find.text('Weight/GSM'), findsOneWidget);
        expect(find.text('320 GSM'), findsOneWidget);
        expect(find.text('Quantity'), findsOneWidget);
        // "280 meters" also appears in the Order Items card behind the
        // sheet, so two matches (not one) confirms the sheet's own copy.
        expect(find.text('280 meters'), findsNWidgets(2));
      },
    );

    testWidgets('Fabric Specs TODO comment exists in source code', (
      tester,
    ) async {
      // Strip only leading "//"/"///" comment markers per line (not every
      // slash in the source — a couple of TODOs below contain a literal
      // "product/backend" that must survive intact).
      final source = File('lib/screens/order_detail_screen.dart')
          .readAsStringSync()
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^\s*/{2,3}\s?'), ''))
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
        source.contains(
          'TODO: Confirm final Fabric Specs behavior with product/backend '
          'team: PDF download, modal, or separate screen.',
        ),
        isTrue,
      );
    });
  });

  group('Order History action', () {
    testWidgets('Order Detail screen renders ORDER HISTORY', (tester) async {
      await _pumpOrderDetailScreen(tester);
      expect(find.text('ORDER HISTORY'), findsOneWidget);
      expect(find.text('VIEW ORDER TIMELINE'), findsOneWidget);
    });

    testWidgets(
      'Tapping ORDER HISTORY shows the placeholder snackbar safely',
      (tester) async {
        await _pumpOrderDetailScreen(tester);

        await tester.tap(
          find.byKey(const ValueKey('order-detail-order-history-button')),
        );
        await tester.pump();

        expect(find.text('Order history coming soon'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'No crash for an order with no dedicated history/timeline data',
      (tester) async {
        // No order in the mock dataset has real history/timeline data yet
        // (no such model exists) - any loaded order exercises this, so the
        // default fixed order doubles as the "missing history data" case.
        await _pumpOrderDetailScreen(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Header and breadcrumb', () {
    testWidgets('Renders breadcrumb and order title', (tester) async {
      await _pumpOrderDetailScreen(tester);

      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('ORD-8829'), findsWidgets);
      expect(find.text('Delivered'), findsOneWidget);
    });
  });
}
