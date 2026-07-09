// Widget checks for the reusable StatusBadge component: correct labels for
// confirmed order statuses, and safe/neutral handling of unknown statuses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/fabric_order.dart';
import 'package:anc_fabrics/widgets/status_badge.dart';

Future<void> _pumpBadge(WidgetTester tester, OrderStatus status) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: StatusBadge(status: status))),
    ),
  );
}

void main() {
  testWidgets('StatusBadge renders the Delivered label', (tester) async {
    await _pumpBadge(tester, OrderStatus.delivered);
    expect(find.text('Delivered'), findsOneWidget);
  });

  testWidgets('StatusBadge renders the Shipped label', (tester) async {
    await _pumpBadge(tester, OrderStatus.shipped);
    expect(find.text('Shipped'), findsOneWidget);
  });

  testWidgets('StatusBadge renders the Processing label', (tester) async {
    await _pumpBadge(tester, OrderStatus.processing);
    expect(find.text('Processing'), findsOneWidget);
  });

  testWidgets('StatusBadge renders a neutral Unknown badge safely', (
    tester,
  ) async {
    await _pumpBadge(tester, OrderStatus.unknown);

    expect(find.text('Unknown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('mapOrderStatus falls back to unknown for unrecognized raw values', () {
    expect(mapOrderStatus('Delivered'), OrderStatus.delivered);
    expect(mapOrderStatus('shipped'), OrderStatus.shipped);
    expect(mapOrderStatus('PROCESSING'), OrderStatus.processing);
    expect(mapOrderStatus('SomeFutureBackendStatus'), OrderStatus.unknown);
    expect(mapOrderStatus(''), OrderStatus.unknown);
  });
}
