// Widget checks for OrderCard: confirms every required data point renders
// (thumbnail area, order ID, date, status badge, fabric tag, meters, price).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/fabric_order.dart';
import 'package:anc_fabrics/widgets/order_card.dart';

void main() {
  testWidgets('OrderCard displays all required order details', (tester) async {
    final order = FabricOrder(
      orderId: '#ORD-8829',
      date: 'Oct 12, 2023',
      orderDate: DateTime(2023, 10, 12),
      status: OrderStatus.delivered,
      fabricTag: 'Premium Cotton Twill',
      fabricType: 'Cotton',
      meters: '280 meters',
      price: '\$4,800.00',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OrderCard(order: order)),
      ),
    );

    // Thumbnail placeholder area.
    expect(find.byIcon(Icons.texture_rounded), findsOneWidget);

    expect(find.text('ORD-8829'), findsOneWidget);
    expect(find.text('Oct 12, 2023'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget); // status badge label
    expect(find.text('Premium Cotton Twill'), findsOneWidget);
    expect(find.text('280 meters'), findsOneWidget);
    expect(find.text('\$4,800.00'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'OrderCard shows a fallback placeholder icon when thumbnailUrl is '
    'missing',
    (tester) async {
      final order = FabricOrder(
        orderId: '#ORD-8830',
        date: 'Oct 18, 2023',
        orderDate: DateTime(2023, 10, 18),
        status: OrderStatus.shipped,
        fabricTag: 'Italian Wool Blend',
        fabricType: 'Wool',
        meters: '150 meters',
        price: '\$6,200.00',
        // thumbnailUrl intentionally omitted (null) — no image asset
        // pipeline/CDN exists yet for any current mock order.
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OrderCard(order: order)),
        ),
      );

      expect(find.byIcon(Icons.texture_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('OrderCard invokes onTap when tapped', (tester) async {
    final order = FabricOrder(
      orderId: '#ORD-8829',
      date: 'Oct 12, 2023',
      orderDate: DateTime(2023, 10, 12),
      status: OrderStatus.delivered,
      fabricTag: 'Premium Cotton Twill',
      fabricType: 'Cotton',
      meters: '280 meters',
      price: '\$4,800.00',
    );

    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderCard(order: order, onTap: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byType(OrderCard));
    expect(tapped, isTrue);
  });
}
