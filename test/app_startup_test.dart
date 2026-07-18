// Tests for MyApp's startup auth gate: given the persisted-session state
// main() resolves before calling runApp, does the app open on Login or on
// an authenticated screen? This is what stops a relaunch after logout from
// reopening on Home (or any other authenticated screen).

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/main.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/login_screen.dart';

void main() {
  testWidgets(
    'Defaults to Login when constructed without an explicit session state '
    '(matches a fresh, logged-out install)',
    (tester) async {
      await tester.pumpWidget(const MyApp());

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets(
    'Opens on Login when the startup session check reports logged out '
    '(e.g. after logout cleared the session)',
    (tester) async {
      await tester.pumpWidget(const MyApp(isLoggedIn: false));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    },
  );

  testWidgets('Opens on Home when the startup session check reports an active '
      'session', (tester) async {
    await tester.pumpWidget(const MyApp(isLoggedIn: true));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
