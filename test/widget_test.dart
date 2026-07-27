// Basic smoke test for the Login Screen.
//The test folder contains automated Flutter widget tests. We added Home screen tests to validate navigation, responsive layout, catalogue lookup states, and pull-to-refresh behavior. These tests do not affect the production app; they are only used during development to make sure future changes do not break the UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anc_fabrics/main.dart';

void main() {
  testWidgets('Login screen renders key content', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('MOBILE NUMBER'), findsOneWidget);
    expect(find.text('CLIENT NAME'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(find.text('BACK'), findsOneWidget);
    expect(find.text('Need help? Contact Us'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
  });

  testWidgets('Password visibility toggle switches obscureText', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp());

    Finder findPasswordField() => find.ancestor(
      of: find.text('Enter your password'),
      matching: find.byType(TextField),
    );

    TextField passwordField = tester.widget(findPasswordField());
    expect(passwordField.obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    passwordField = tester.widget(findPasswordField());
    expect(passwordField.obscureText, isFalse);
  });

  // These tests drive the real Login screen via MyApp/LoginScreen (not an
  // isolated CountryCodePicker instance) so they catch regressions where the
  // screen ends up wired to a stale/old picker or list.
  group('Login screen country code picker (real screen, not isolated)', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.pumpWidget(MyApp());
      expect(find.text('+971'), findsOneWidget); // default selection: UAE
      await tester.tap(find.text('+971'));
      await tester.pumpAndSettle();
    }

    Future<void> search(WidgetTester tester, String query) async {
      final searchField = find.byType(TextField).last;
      await tester.enterText(searchField, query);
      await tester.pumpAndSettle();
    }

    testWidgets('Lebanon appears in the picker list', (tester) async {
      await openPicker(tester);
      expect(find.text('Lebanon'), findsOneWidget);
      expect(find.text('🇱🇧'), findsOneWidget);
    });

    testWidgets('Iraq appears in the picker list', (tester) async {
      await openPicker(tester);
      expect(find.text('Iraq'), findsOneWidget);
      expect(find.text('🇮🇶'), findsOneWidget);
    });

    testWidgets('Searching "Lebanon" returns Lebanon', (tester) async {
      await openPicker(tester);
      // Partial query so it doesn't also match the search field's own
      // EditableText content, which find.text() also matches on.
      await search(tester, 'Leban');
      expect(find.text('Lebanon'), findsOneWidget);
      expect(find.text('Iraq'), findsNothing);
    });

    testWidgets('Searching "961" returns Lebanon', (tester) async {
      await openPicker(tester);
      await search(tester, '961');
      expect(find.text('Lebanon'), findsOneWidget);
      expect(find.text('Iraq'), findsNothing);
    });

    testWidgets('Searching "LB" returns Lebanon', (tester) async {
      await openPicker(tester);
      await search(tester, 'LB');
      expect(find.text('Lebanon'), findsOneWidget);
      expect(find.text('Iraq'), findsNothing);
    });

    testWidgets('Searching "Iraq" returns Iraq', (tester) async {
      await openPicker(tester);
      await search(tester, 'Ira');
      expect(find.text('Iraq'), findsOneWidget);
      expect(find.text('Lebanon'), findsNothing);
    });

    testWidgets('Searching "964" returns Iraq', (tester) async {
      await openPicker(tester);
      await search(tester, '964');
      expect(find.text('Iraq'), findsOneWidget);
      expect(find.text('Lebanon'), findsNothing);
    });

    testWidgets('Searching "IQ" returns Iraq', (tester) async {
      await openPicker(tester);
      await search(tester, 'IQ');
      expect(find.text('Iraq'), findsOneWidget);
      expect(find.text('Lebanon'), findsNothing);
    });

    testWidgets('Searching with no match shows "No countries found"', (
      tester,
    ) async {
      await openPicker(tester);
      await search(tester, 'zzz');
      expect(find.text('No countries found'), findsOneWidget);
    });

    testWidgets('Selecting Lebanon updates the selected display to 🇱🇧 +961', (
      tester,
    ) async {
      await openPicker(tester);
      await tester.tap(find.text('Lebanon'));
      await tester.pumpAndSettle();

      expect(find.text('+961'), findsOneWidget);
      expect(find.text('🇱🇧'), findsOneWidget);
      expect(find.text('+971'), findsNothing);
    });

    testWidgets('Selecting Iraq updates the selected display to 🇮🇶 +964', (
      tester,
    ) async {
      await openPicker(tester);
      await tester.tap(find.text('Iraq'));
      await tester.pumpAndSettle();

      expect(find.text('+964'), findsOneWidget);
      expect(find.text('🇮🇶'), findsOneWidget);
      expect(find.text('+971'), findsNothing);
    });

    testWidgets(
      'Selected dial code combines with the mobile number for login',
      (tester) async {
        await openPicker(tester);
        await tester.tap(find.text('Lebanon'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, '50 123 4567'),
          '70123456',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Enter your password'),
          'secret123',
        );
        await tester.pump();

        // The full phone value (+961 + 70123456) is assembled internally in
        // _handleLogin; this just confirms the selected code and number are
        // both present and correctly wired ahead of that combination.
        expect(find.text('+961'), findsOneWidget);
        expect(find.text('70123456'), findsOneWidget);
      },
    );
  });
}
