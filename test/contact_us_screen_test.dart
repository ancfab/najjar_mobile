// Widget checks for the Contact Us screen: navigation from/to the Support
// landing screen, intro/summary content, form validation, subject
// selection, and the placeholder "not connected yet" submission.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';

void main() {
  Future<void> pumpSupport(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpContactUs(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ContactUsScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> fillValidForm(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('contact-full-name-field')),
      'Jane Weaver',
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-work-email-field')),
      'jane@textile.co',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('contact-subject-field')),
    );
    await tester.tap(find.byKey(const ValueKey('contact-subject-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Technical Support').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-message-field')),
      'We need help scheduling a shipment.',
    );
  }

  group('Navigation integration', () {
    testWidgets('Tapping EMAIL SUPPORT opens ContactUsScreen', (tester) async {
      await pumpSupport(tester);

      await tester.tap(find.byKey(const ValueKey('support-email-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ContactUsScreen), findsOneWidget);
      expect(find.byType(SupportScreen), findsNothing);
    });

    testWidgets('Screen displays Back to Support', (tester) async {
      await pumpContactUs(tester);

      expect(find.text('Back to Support'), findsOneWidget);
    });

    testWidgets('Tapping Back to Support returns to SupportScreen', (
      tester,
    ) async {
      await pumpSupport(tester);

      await tester.tap(find.byKey(const ValueKey('support-email-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ContactUsScreen), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('contact-back-to-support-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SupportScreen), findsOneWidget);
      expect(find.byType(ContactUsScreen), findsNothing);
    });
  });

  group('Screen content', () {
    testWidgets('Displays intro, contact summary, and form', (tester) async {
      await pumpContactUs(tester);

      expect(find.text('SUPPORT CENTER'), findsOneWidget);
      expect(find.text('Contact Us'), findsWidgets);
      expect(
        find.text(
          'Connect with our textile experts to streamline your supply '
          'chain or inquire about our premium weave collections.',
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey('contact-full-name-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-work-email-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-subject-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('contact-message-field')),
        findsOneWidget,
      );
      expect(find.text('SEND EMAIL'), findsOneWidget);

      expect(find.text('EMAIL US'), findsOneWidget);
      expect(find.text('MAIN OFFICE'), findsOneWidget);
      expect(
        find.text('Support email details will be added soon.'),
        findsOneWidget,
      );
      expect(
        find.text('Office details for UAE will be added soon.'),
        findsOneWidget,
      );
    });
  });

  group('Form validation', () {
    testWidgets('Empty submission shows required validation', (tester) async {
      await pumpContactUs(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your full name.'), findsOneWidget);
      expect(find.text('Please enter your work email.'), findsOneWidget);
      expect(find.text('Please select a subject.'), findsOneWidget);
      expect(find.text('Please enter a message.'), findsOneWidget);
      expect(
        find.text('Email support submission is not connected yet.'),
        findsNothing,
      );
    });

    testWidgets('Invalid email shows email validation', (tester) async {
      await pumpContactUs(tester);

      await tester.enterText(
        find.byKey(const ValueKey('contact-full-name-field')),
        'Jane Weaver',
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-work-email-field')),
        'not-an-email',
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-message-field')),
        'Hello there',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address.'), findsOneWidget);
    });
  });

  group('Subject selection', () {
    testWidgets('Selecting a subject updates the displayed value', (
      tester,
    ) async {
      await pumpContactUs(tester);

      expect(find.text('Select a subject'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-subject-field')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-subject-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invoice or Payment').last);
      await tester.pumpAndSettle();

      expect(find.text('Invoice or Payment'), findsOneWidget);
    });
  });

  group('Placeholder submission', () {
    testWidgets('Valid submission shows the not-connected SnackBar', (
      tester,
    ) async {
      await pumpContactUs(tester);

      await fillValidForm(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pump();

      expect(
        find.text('Email support submission is not connected yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Let the brief resubmission-guard timer finish inside the test.
      await tester.pumpAndSettle();
    });
  });

  group('Responsive coverage', () {
    const sizes = [
      Size(320, 568),
      Size(375, 667),
      Size(768, 1024),
      Size(844, 390),
    ];

    for (final size in sizes) {
      testWidgets(
        'No overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await pumpContactUs(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('No overflow at 1.5x system text scale', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpContactUs(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Keyboard safety', () {
    testWidgets(
      'Message body remains reachable when the keyboard opens on a small '
      'screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpContactUs(tester);

        await tester.ensureVisible(
          find.byKey(const ValueKey('contact-message-field')),
        );
        await tester.tap(find.byKey(const ValueKey('contact-message-field')));
        await tester.pumpAndSettle();

        // Simulate the on-screen keyboard occupying the bottom portion of
        // the small viewport.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(() => tester.view.resetViewInsets());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('contact-message-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('contact-send-email-button')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
