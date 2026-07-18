// Widget checks for the Edit Profile screen: header/back button, avatar +
// camera overlay, client info, prefilled form fields (including multiline
// Business Address), Save Changes submission against a fake in-memory
// service, the Logout placeholder, bottom navigation (Profile selected),
// scroll-to-Logout on a small viewport, and real back navigation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/data/mock_profile_data.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/profile_service.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';

import 'helpers/fake_profile_service.dart';

void main() {
  Future<void> pumpEditProfile(
    WidgetTester tester, {
    double width = 390,
    double height = 800,
    FakeProfileService? service,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: EditProfileScreen(service: service ?? FakeProfileService()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Reads a field's live controller text directly, matching the pattern
  // used by contact_us_screen_test.dart for the same reason: hint text can
  // otherwise collide with entered/prefilled values.
  String fieldText(WidgetTester tester, Key key) {
    return tester.widget<TextFormField>(find.byKey(key)).controller!.text;
  }

  group('Header', () {
    testWidgets('Shows the Edit Profile title and back button', (tester) async {
      await pumpEditProfile(tester);

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('edit-profile-back-button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });
  });

  group('Avatar', () {
    testWidgets('Shows the avatar and camera/edit overlay', (tester) async {
      await pumpEditProfile(tester);

      expect(find.byKey(const ValueKey('edit-profile-avatar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('edit-profile-camera-button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    });

    testWidgets('Tapping the camera overlay shows a placeholder message', (
      tester,
    ) async {
      await pumpEditProfile(tester);

      await tester.tap(
        find.byKey(const ValueKey('edit-profile-camera-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Profile photo upload is not available yet.'),
        findsOneWidget,
      );
    });
  });

  group('Client info', () {
    testWidgets('Shows the ANC ID and profile-updated text', (tester) async {
      await pumpEditProfile(tester);

      expect(find.text('ANC ID: #${kMockUserProfile.ancId}'), findsOneWidget);
      expect(find.text(kMockUserProfile.profileUpdatedLabel), findsOneWidget);
    });
  });

  group('Form fields', () {
    testWidgets('All five fields render with the expected initial values', (
      tester,
    ) async {
      await pumpEditProfile(tester);

      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('Company'), findsOneWidget);
      expect(find.text('Business Address'), findsOneWidget);

      expect(
        fieldText(tester, const ValueKey('edit-profile-full-name-field')),
        kMockUserProfile.fullName,
      );
      expect(
        fieldText(tester, const ValueKey('edit-profile-email-field')),
        kMockUserProfile.email,
      );
      expect(
        fieldText(tester, const ValueKey('edit-profile-phone-field')),
        kMockUserProfile.phone,
      );
      expect(
        fieldText(tester, const ValueKey('edit-profile-company-field')),
        kMockUserProfile.company,
      );
      expect(
        fieldText(
          tester,
          const ValueKey('edit-profile-business-address-field'),
        ),
        kMockUserProfile.businessAddress,
      );
    });

    testWidgets('Business Address field supports multiline content', (
      tester,
    ) async {
      await pumpEditProfile(tester);

      final key = const ValueKey('edit-profile-business-address-field');

      await tester.ensureVisible(find.byKey(key));
      await tester.enterText(find.byKey(key), 'Line one\nLine two\nLine three');
      await tester.pump();

      expect(fieldText(tester, key), 'Line one\nLine two\nLine three');
    });
  });

  group('Save Changes', () {
    testWidgets('Renders the Save Changes button', (tester) async {
      await pumpEditProfile(tester);

      expect(
        find.byKey(const ValueKey('edit-profile-save-button')),
        findsOneWidget,
      );
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets(
      'Save Changes is disabled until a field differs from the loaded profile',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);

        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(service.submittedRequests, isEmpty);
      },
    );

    testWidgets('Submits the current field values to the injected service', (
      tester,
    ) async {
      final service = FakeProfileService();
      await pumpEditProfile(tester, service: service);

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-full-name-field')),
        'Alexandra Mitchell',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(service.submittedRequests, hasLength(1));
      final request = service.submittedRequests.single;
      expect(request.fullName, 'Alexandra Mitchell');
      expect(request.email, kMockUserProfile.email);
      expect(request.phone, kMockUserProfile.phone);
      expect(request.company, kMockUserProfile.company);
      expect(request.businessAddress, kMockUserProfile.businessAddress);
    });

    testWidgets(
      'Trims leading/trailing whitespace before treating a field as changed',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          '  ${kMockUserProfile.fullName}  ',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(service.submittedRequests, isEmpty);
      },
    );

    testWidgets(
      'Blocks submission and shows an error when Full Name is empty',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          '',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Please enter your full name.'), findsOneWidget);
        expect(service.submittedRequests, isEmpty);
      },
    );

    testWidgets(
      'Blocks submission and shows an error when Email Address is malformed',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-email-field')),
          'not-an-email',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Please enter a valid email address.'),
          findsOneWidget,
        );
        expect(service.submittedRequests, isEmpty);
      },
    );

    testWidgets(
      'Blocks submission and shows an error when Phone Number is empty',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-phone-field')),
          '',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Please enter your phone number.'), findsOneWidget);
        expect(service.submittedRequests, isEmpty);
      },
    );

    testWidgets('Blocks submission and shows an error when Phone Number has an '
        'invalid format', (tester) async {
      final service = FakeProfileService();
      await pumpEditProfile(tester, service: service);

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-phone-field')),
        'call-me-maybe',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid phone number.'), findsOneWidget);
      expect(service.submittedRequests, isEmpty);
    });

    testWidgets(
      'Restoring a field to its original value makes the form clean again',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);
        final key = const ValueKey('edit-profile-full-name-field');

        await tester.enterText(find.byKey(key), 'Someone Else');
        await tester.pump();
        await tester.enterText(find.byKey(key), kMockUserProfile.fullName);
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(service.submittedRequests, isEmpty);
      },
    );

    testWidgets(
      'A successful save makes the form clean again (no false-positive '
      'dirty state)',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          'Alexandra Mitchell',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();
        expect(service.submittedRequests, hasLength(1));

        // Tapping Save again immediately (nothing changed since the save
        // above) must not submit a second, identical request.
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();
        expect(service.submittedRequests, hasLength(1));
      },
    );

    testWidgets('Shows a success message after a successful save', (
      tester,
    ) async {
      final service = FakeProfileService();
      await pumpEditProfile(tester, service: service);

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-full-name-field')),
        'Alexandra Mitchell',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('Profile updated.'), findsOneWidget);
    });

    testWidgets(
      'Does not claim success when the update service is unavailable',
      (tester) async {
        final service = FakeProfileService(
          result: ProfileUpdateResult.unavailable,
        );
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-company-field')),
          'Sterling Freight Co.',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Profile updates are not connected yet.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Shows a loading spinner and blocks a second submission while a '
      'request is in flight',
      (tester) async {
        final pending = Completer<ProfileUpdateResult>();
        final service = FakeProfileService(pending: pending);
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          'Alexandra Mitchell',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Save Changes'), findsNothing);

        // Tapping again while the first request is still in flight must
        // not submit a duplicate request.
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pump();
        expect(service.submittedRequests, hasLength(1));

        pending.complete(
          const ProfileUpdateResult(ProfileUpdateOutcome.success),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Save Changes'), findsOneWidget);
      },
    );

    testWidgets('Shows the service-provided message when the update fails', (
      tester,
    ) async {
      final service = FakeProfileService(
        result: const ProfileUpdateResult(
          ProfileUpdateOutcome.failure,
          message: 'The server rejected that email address.',
        ),
      );
      await pumpEditProfile(tester, service: service);

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-full-name-field')),
        'Alexandra Mitchell',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('The server rejected that email address.'),
        findsOneWidget,
      );
      // The submitted edit must still be on the form, not reset/cleared,
      // so the user can retry the save without retyping it.
      expect(
        fieldText(tester, const ValueKey('edit-profile-full-name-field')),
        'Alexandra Mitchell',
      );
    });

    testWidgets(
      'Shows a generic error message, not a crash, when the service throws',
      (tester) async {
        final service = FakeProfileService(result: Exception('boom'));
        await pumpEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          'Alexandra Mitchell',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text("We couldn't save your changes. Please try again."),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Logout', () {
    testWidgets('Renders a red, full-width Logout button', (tester) async {
      await pumpEditProfile(tester);

      final key = const ValueKey('edit-profile-logout-button');
      expect(find.byKey(key), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);

      final material = tester.widget<Material>(
        find
            .ancestor(of: find.byKey(key), matching: find.byType(Material))
            .first,
      );
      expect(material.color, const Color(0xFFEE2B2B));

      final sizedBox = tester.widget<SizedBox>(
        find
            .descendant(of: find.byKey(key), matching: find.byType(SizedBox))
            .first,
      );
      expect(sizedBox.width, double.infinity);
    });

    testWidgets('Tapping Logout shows a placeholder message, not a fake '
        'success state', (tester) async {
      await pumpEditProfile(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-logout-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('edit-profile-logout-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Logout is not connected yet.'), findsOneWidget);
    });
  });

  group('Bottom navigation', () {
    testWidgets('Reuses CustomBottomNav with Profile selected', (tester) async {
      await pumpEditProfile(tester);

      expect(find.byType(CustomBottomNav), findsOneWidget);
      expect(find.byType(CustomBottomNavItem), findsNWidgets(4));

      final bottomNav = tester.widget<CustomBottomNav>(
        find.byType(CustomBottomNav),
      );
      expect(bottomNav.currentIndex, 3);
    });

    testWidgets('Selecting Orders and Support pushes each screen', (
      tester,
    ) async {
      await pumpEditProfile(tester);

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
    });

    testWidgets(
      'Selecting Profile is a no-op: this screen is already the Profile '
      'tab\'s destination',
      (tester) async {
        await pumpEditProfile(tester);

        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();

        expect(find.byType(EditProfileScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Small viewport scrolling', () {
    testWidgets('Can scroll to the Logout button without overflow', (
      tester,
    ) async {
      await pumpEditProfile(tester, width: 320, height: 560);

      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-logout-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit-profile-logout-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive layout', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      testWidgets('No overflow at ${width}px width', (tester) async {
        await pumpEditProfile(tester, width: width);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('No overflow with the keyboard open on a small viewport', (
      tester,
    ) async {
      await pumpEditProfile(tester, width: 320, height: 560);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-full-name-field')),
        'Alexander Mitchell',
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Back navigation', () {
    Future<void> pumpPushedEditProfile(
      WidgetTester tester, {
      FakeProfileService? service,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(
                        service: service ?? FakeProfileService(),
                      ),
                    ),
                  ),
                  child: const Text('Open Edit Profile'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Edit Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
    }

    testWidgets('Back button pops back to the previous screen', (tester) async {
      await pumpPushedEditProfile(tester);

      await tester.tap(find.byKey(const ValueKey('edit-profile-back-button')));
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text('Open Edit Profile'), findsOneWidget);
    });

    testWidgets(
      'Clean back navigation exits without showing a discard dialog',
      (tester) async {
        await pumpPushedEditProfile(tester);

        await tester.tap(
          find.byKey(const ValueKey('edit-profile-back-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('edit-profile-discard-dialog')),
          findsNothing,
        );
        expect(find.byType(EditProfileScreen), findsNothing);
      },
    );

    testWidgets(
      'Back button shows a discard-changes dialog when the form is dirty',
      (tester) async {
        await pumpPushedEditProfile(tester);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          'Someone Else',
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('edit-profile-back-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('edit-profile-discard-dialog')),
          findsOneWidget,
        );
        // Still on the form — a blocked pop must not navigate away.
        expect(find.byType(EditProfileScreen), findsOneWidget);
      },
    );

    testWidgets('"Keep Editing" dismisses the dialog and preserves the edit', (
      tester,
    ) async {
      await pumpPushedEditProfile(tester);

      final nameKey = const ValueKey('edit-profile-full-name-field');
      await tester.enterText(find.byKey(nameKey), 'Someone Else');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('edit-profile-back-button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('edit-profile-discard-cancel')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byKey(nameKey)).controller!.text,
        'Someone Else',
      );
    });

    testWidgets('"Discard" pops back and discards the edit', (tester) async {
      await pumpPushedEditProfile(tester);

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-full-name-field')),
        'Someone Else',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('edit-profile-back-button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('edit-profile-discard-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text('Open Edit Profile'), findsOneWidget);
    });

    testWidgets(
      'No discard dialog appears when leaving right after a successful save',
      (tester) async {
        final service = FakeProfileService();
        await pumpPushedEditProfile(tester, service: service);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          'Someone Else',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();
        expect(service.submittedRequests, hasLength(1));

        await tester.tap(
          find.byKey(const ValueKey('edit-profile-back-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('edit-profile-discard-dialog')),
          findsNothing,
        );
        expect(find.byType(EditProfileScreen), findsNothing);
        expect(find.text('Open Edit Profile'), findsOneWidget);
      },
    );
  });
}
