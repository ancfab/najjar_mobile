//The test folder contains automated Flutter widget tests. We added Home screen tests to validate navigation, responsive layout, catalogue lookup states, and pull-to-refresh behavior. These tests do not affect the production app; they are only used during development to make sure future changes do not break the UI.
// Widget checks for the Home screen: narrow-width overflow safety and the
// navigation wiring for the Scan CTA and bottom tab bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/screens/account_balance_screen.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/profile_screen.dart';
import 'package:anc_fabrics/screens/scan_stock_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/widgets/balance_card.dart';

Future<void> _pumpHomeScreen(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  // Home screen loads dashboard data via a mock delay on initState; advance
  // past it explicitly since pumpAndSettle won't wait for a bare Timer that
  // isn't tied to a scheduled frame.
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('Home screen has no overflow at ${width}px width', (
      tester,
    ) async {
      await _pumpHomeScreen(tester, width);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Scan Fabric Availability CTA opens the Scan Stock screen', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.tap(find.text('Scan Fabric Availability'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanStockScreen), findsOneWidget);
    expect(find.text('Scan Stock'), findsOneWidget);
    expect(find.text('Center the QR code within the frame'), findsOneWidget);
  });

  testWidgets('Bottom tabs navigate to Orders, Support, and Profile', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.byType(OrdersScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.byType(SupportScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('Catalogue lookup shows a validation error on empty input', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();

    expect(find.text('Please enter a catalogue code.'), findsOneWidget);
  });

  testWidgets('Catalogue lookup shows loading then a success result', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.enterText(find.byType(TextField), 'FAB-1001');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('320 yd available at Warehouse A.'), findsOneWidget);
  });

  testWidgets('Catalogue lookup shows a no-results state for unknown codes', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.enterText(find.byType(TextField), 'UNKNOWN-CODE');
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.text('No availability found for "UNKNOWN-CODE".'),
      findsOneWidget,
    );
  });

  testWidgets('Pull-to-refresh reloads the dashboard without errors', (
    tester,
  ) async {
    await _pumpHomeScreen(tester, 390);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BalanceCard), findsOneWidget);
  });

  group('Current Balance card navigation', () {
    testWidgets('Home screen renders the Current Balance card', (tester) async {
      await _pumpHomeScreen(tester, 390);

      expect(find.byType(BalanceCard), findsOneWidget);
    });

    testWidgets('Tapping the Current Balance card opens AccountBalanceScreen', (
      tester,
    ) async {
      await _pumpHomeScreen(tester, 390);

      await tester.tap(find.byType(BalanceCard));
      await tester.pumpAndSettle();

      expect(find.byType(AccountBalanceScreen), findsOneWidget);
    });

    testWidgets('Back navigation from AccountBalanceScreen returns to Home', (
      tester,
    ) async {
      await _pumpHomeScreen(tester, 390);

      await tester.tap(find.byType(BalanceCard));
      await tester.pumpAndSettle();
      expect(find.byType(AccountBalanceScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AccountBalanceScreen), findsNothing);
    });

    testWidgets(
      'Selecting Home from AccountBalanceScreen bottom nav returns to Home '
      'without creating a duplicate Home screen',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        await tester.tap(find.byType(BalanceCard));
        await tester.pumpAndSettle();
        expect(find.byType(AccountBalanceScreen), findsOneWidget);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(AccountBalanceScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Repeated opening and returning does not create navigation errors',
      (tester) async {
        await _pumpHomeScreen(tester, 390);

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byType(BalanceCard));
          await tester.pumpAndSettle();
          expect(find.byType(AccountBalanceScreen), findsOneWidget);

          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(HomeScreen), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      },
    );
  });
}
