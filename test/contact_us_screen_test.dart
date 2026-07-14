// Widget checks for the Contact Us screen: navigation from/to the Support
// landing screen, intro/summary content, form validation, the subject
// dropdown's source of truth, submission (success/failure/loading/retry)
// against a fake in-memory service, and profile prefill behavior.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/support_regions_data.dart';
import 'package:anc_fabrics/models/contact_subject.dart';
import 'package:anc_fabrics/models/support_region.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/contact_support_service.dart';

import 'helpers/fake_contact_support_service.dart';

void main() {
  Future<void> pumpSupport(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpContactUs(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ContactUsScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> fillValidForm(
    WidgetTester tester, {
    String subjectLabel = 'Technical Support',
  }) async {
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
    await tester.tap(find.text(subjectLabel).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-message-field')),
      'We need help scheduling a shipment.',
    );
  }

  // Reads a field's live controller text directly rather than via
  // find.text(...), since the full name/email fields' hintText ('Jane
  // Weaver' / 'jane@textile.co') stays mounted (only faded, not removed)
  // once the field has content, and would otherwise produce a false
  // "found 2" match whenever a test's entered value happens to equal the
  // hint sample.
  String fieldText(WidgetTester tester, Key key) {
    return tester.widget<TextFormField>(find.byKey(key)).controller!.text;
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

    testWidgets('Tapping EMAIL SUPPORT passes the currently selected region to '
        'ContactUsScreen', (tester) async {
      await pumpSupport(tester);

      final lebanon = kSupportRegions.firstWhere(
        (region) => region.id == SupportRegionId.lebanon,
      );
      await tester.tap(find.text(lebanon.displayName));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('support-email-button')));
      await tester.pumpAndSettle();

      final contactUsScreen = tester.widget<ContactUsScreen>(
        find.byType(ContactUsScreen),
      );
      expect(contactUsScreen.region?.id, lebanon.id);
      expect(
        find.text(
          'Office details for ${lebanon.displayName} will be added soon.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Office details for UAE will be added soon.'),
        findsNothing,
      );
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

    testWidgets('Does not call the contact service when validation fails', (
      tester,
    ) async {
      final service = FakeContactSupportService();
      await tester.pumpWidget(
        MaterialApp(home: ContactUsScreen(contactService: service)),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(service.submittedRequests, isEmpty);
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

  group('Subject dropdown source of truth', () {
    testWidgets('Every subject defined by ContactSubject.values appears in the '
        'dropdown, in the same order', (tester) async {
      await pumpContactUs(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-subject-field')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-subject-field')));
      await tester.pumpAndSettle();

      final labels = [for (final s in ContactSubject.values) s.label];
      final positions = <double>[];
      for (final label in labels) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: 'Missing subject: $label');
        positions.add(tester.getTopLeft(finder).dy);
      }

      for (var i = 0; i < positions.length - 1; i++) {
        expect(
          positions[i],
          lessThan(positions[i + 1]),
          reason: 'Expected "${labels[i]}" to appear above "${labels[i + 1]}"',
        );
      }
    });

    // One isolated test per subject (rather than looping subjects inside a
    // single test) so a fresh widget tree/binding backs each selection —
    // matching the "Responsive coverage" group's per-case pattern below.
    for (final subject in ContactSubject.values) {
      testWidgets(
        'Selecting "${subject.label}" sends ContactSubject.${subject.name} '
        'as the request subject',
        (tester) async {
          final service = FakeContactSupportService();
          await tester.pumpWidget(
            MaterialApp(home: ContactUsScreen(contactService: service)),
          );
          await tester.pumpAndSettle();

          await fillValidForm(tester, subjectLabel: subject.label);
          await tester.ensureVisible(
            find.byKey(const ValueKey('contact-send-email-button')),
          );
          await tester.tap(
            find.byKey(const ValueKey('contact-send-email-button')),
          );
          await tester.pumpAndSettle();

          expect(service.submittedRequests, hasLength(1));
          expect(service.submittedRequests.single.subject, subject);
        },
      );
    }
  });

  group('Placeholder submission (no backend configured)', () {
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
      await tester.pumpAndSettle();

      expect(
        find.text('Email support submission is not connected yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Contact submission (fake service)', () {
    Future<void> pumpWithService(
      WidgetTester tester,
      ContactSupportService service, {
      SupportRegionData? region,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ContactUsScreen(contactService: service, region: region),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'A valid submission calls the service exactly once with trimmed '
      'name, email, message, and the current region',
      (tester) async {
        final service = FakeContactSupportService();
        final lebanon = kSupportRegions.firstWhere(
          (region) => region.id == SupportRegionId.lebanon,
        );
        await pumpWithService(tester, service, region: lebanon);

        await tester.enterText(
          find.byKey(const ValueKey('contact-full-name-field')),
          '  Jane Weaver  ',
        );
        await tester.enterText(
          find.byKey(const ValueKey('contact-work-email-field')),
          '  jane@textile.co  ',
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
          '  We need help scheduling a shipment.  ',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.pumpAndSettle();

        expect(service.submittedRequests, hasLength(1));
        final request = service.submittedRequests.single;
        expect(request.name, 'Jane Weaver');
        expect(request.email, 'jane@textile.co');
        expect(request.subject, ContactSubject.technicalSupport);
        expect(request.message, 'We need help scheduling a shipment.');
        expect(request.regionId, lebanon.id);
      },
    );

    testWidgets('Shows a loading state while the submission is pending', (
      tester,
    ) async {
      final pending = Completer<ContactSubmissionResult>();
      final service = FakeContactSupportService(pending: pending);
      await pumpWithService(tester, service);
      await fillValidForm(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete(ContactSubmissionResult.success);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Rapid repeated taps only submit once', (tester) async {
      final pending = Completer<ContactSubmissionResult>();
      final service = FakeContactSupportService(pending: pending);
      await pumpWithService(tester, service);
      await fillValidForm(tester);

      final button = find.byKey(const ValueKey('contact-send-email-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.tap(button);

      expect(service.submittedRequests, hasLength(1));

      pending.complete(ContactSubmissionResult.success);
      await tester.pumpAndSettle();

      expect(service.submittedRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Success confirmation is shown only after the service reports '
        'success, and no error/unavailable message appears', (tester) async {
      final service = FakeContactSupportService(
        result: ContactSubmissionResult.success,
      );
      await pumpWithService(tester, service);
      await fillValidForm(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Thanks — we've received your message and will be in touch "
          'soon.',
        ),
        findsOneWidget,
      );
      expect(
        find.text("We couldn't send your message. Please try again."),
        findsNothing,
      );
      expect(
        find.text('Email support submission is not connected yet.'),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'A failure result shows the approved error message and keeps form '
      'values available for retry',
      (tester) async {
        final service = FakeContactSupportService(
          result: const ContactSubmissionResult(
            ContactSubmissionOutcome.failure,
          ),
        );
        await pumpWithService(tester, service);
        await fillValidForm(tester);

        await tester.ensureVisible(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('contact-send-email-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text("We couldn't send your message. Please try again."),
          findsOneWidget,
        );
        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Jane Weaver',
        );
        expect(
          fieldText(tester, const ValueKey('contact-work-email-field')),
          'jane@textile.co',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('A thrown exception does not crash the screen and shows the '
        'approved error message', (tester) async {
      final service = FakeContactSupportService(
        result: Exception('network unreachable'),
      );
      await pumpWithService(tester, service);
      await fillValidForm(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('contact-send-email-button')),
      );
      await tester.tap(find.byKey(const ValueKey('contact-send-email-button')));
      await tester.pumpAndSettle();

      expect(
        find.text("We couldn't send your message. Please try again."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('The user can retry successfully after a failure', (
      tester,
    ) async {
      final service = FakeContactSupportService(
        result: const ContactSubmissionResult(ContactSubmissionOutcome.failure),
      );
      await pumpWithService(tester, service);
      await fillValidForm(tester);

      final button = find.byKey(const ValueKey('contact-send-email-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text("We couldn't send your message. Please try again."),
        findsOneWidget,
      );

      service.result = ContactSubmissionResult.success;
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Thanks — we've received your message and will be in touch "
          'soon.',
        ),
        findsOneWidget,
      );
      expect(service.submittedRequests, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('Profile prefill', () {
    testWidgets('Prefills name and email when initial values are supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ContactUsScreen(
            initialName: 'Jane Weaver',
            initialEmail: 'jane@textile.co',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        fieldText(tester, const ValueKey('contact-full-name-field')),
        'Jane Weaver',
      );
      expect(
        fieldText(tester, const ValueKey('contact-work-email-field')),
        'jane@textile.co',
      );
    });

    testWidgets('Prefilled fields remain editable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ContactUsScreen(initialName: 'Jane Weaver')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('contact-full-name-field')),
        'Jane Edited',
      );
      await tester.pump();

      expect(
        fieldText(tester, const ValueKey('contact-full-name-field')),
        'Jane Edited',
      );
    });

    testWidgets(
      "A rebuild with the same initial value does not reset a user's edit",
      (tester) async {
        final rebuildTrigger = ValueNotifier<int>(0);
        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: rebuildTrigger,
              builder: (context, _) =>
                  const ContactUsScreen(initialName: 'Jane Weaver'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('contact-full-name-field')),
          'Jane Edited',
        );
        await tester.pump();

        rebuildTrigger.value++;
        await tester.pumpAndSettle();

        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Jane Edited',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Late-arriving profile data does not overwrite a field the user has '
      'already edited',
      (tester) async {
        final initialName = ValueNotifier<String?>(null);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<String?>(
              valueListenable: initialName,
              builder: (context, value, _) =>
                  ContactUsScreen(initialName: value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('contact-full-name-field')),
          'Customer Typed Name',
        );
        await tester.pump();

        // Simulate the profile/session value arriving asynchronously after
        // the customer has already started typing.
        initialName.value = 'Jane Weaver';
        await tester.pumpAndSettle();

        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Customer Typed Name',
        );
      },
    );

    testWidgets(
      'Late-arriving profile data fills a still-empty, untouched field',
      (tester) async {
        final initialName = ValueNotifier<String?>(null);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<String?>(
              valueListenable: initialName,
              builder: (context, value, _) =>
                  ContactUsScreen(initialName: value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        initialName.value = 'Jane Weaver';
        await tester.pumpAndSettle();

        expect(
          fieldText(tester, const ValueKey('contact-full-name-field')),
          'Jane Weaver',
        );
      },
    );

    testWidgets('With no profile data, fields remain empty and usable', (
      tester,
    ) async {
      await pumpContactUs(tester);

      expect(fieldText(tester, const ValueKey('contact-full-name-field')), '');
      await tester.enterText(
        find.byKey(const ValueKey('contact-full-name-field')),
        'Someone Else',
      );
      await tester.pump();
      expect(
        fieldText(tester, const ValueKey('contact-full-name-field')),
        'Someone Else',
      );
      expect(tester.takeException(), isNull);
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
