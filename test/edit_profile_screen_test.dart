// Widget checks for the Edit Profile screen: header/back button, avatar +
// camera overlay, client info, prefilled form fields (including multiline
// Business Address), Save Changes submission against a fake in-memory
// service, confirmation that Logout is hidden (per the approved Figma, with
// the implementation preserved behind a disabled flag for later
// restoration), bottom navigation (Profile selected), responsive/overflow
// safety, and real back navigation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/data/mock_profile_data.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/services/avatar_image_processor.dart';
import 'package:anc_fabrics/services/avatar_permission_service.dart';
import 'package:anc_fabrics/services/avatar_picker_service.dart';
import 'package:anc_fabrics/services/avatar_upload_service.dart';
import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/services/profile_service.dart';
import 'package:anc_fabrics/services/session_storage_exception.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';

import 'helpers/fake_avatar_cropper_service.dart';
import 'helpers/fake_avatar_image_processor.dart';
import 'helpers/fake_avatar_permission_service.dart';
import 'helpers/fake_avatar_picker_service.dart';
import 'helpers/fake_avatar_upload_service.dart';
import 'helpers/fake_logout_service.dart';
import 'helpers/fake_profile_service.dart';

void main() {
  // CurrentUserAvatarController.setAvatarPath/restorePersisted/clear read
  // and write SharedPreferences; without a mock configured, the platform
  // channel call has no handler in a widget test and never resolves,
  // hanging any test that reaches it.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpEditProfile(
    WidgetTester tester, {
    double width = 390,
    double height = 800,
    FakeProfileService? service,
    FakeLogoutService? logoutService,
    FakeAvatarPickerService? avatarPickerService,
    FakeAvatarPermissionService? avatarPermissionService,
    FakeAvatarCropperService? avatarCropperService,
    FakeAvatarImageProcessor? avatarImageProcessor,
    FakeAvatarUploadService? avatarUploadService,
    CurrentUserAvatarController? avatarController,
    bool showLogoutAction = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: EditProfileScreen(
          service: service ?? FakeProfileService(),
          logoutService: logoutService ?? FakeLogoutService(),
          avatarPickerService: avatarPickerService ?? FakeAvatarPickerService(),
          avatarPermissionService:
              avatarPermissionService ?? FakeAvatarPermissionService(),
          avatarCropperService:
              avatarCropperService ?? FakeAvatarCropperService(),
          avatarImageProcessor:
              avatarImageProcessor ?? FakeAvatarImageProcessor(),
          avatarUploadService: avatarUploadService ?? FakeAvatarUploadService(),
          avatarController: avatarController ?? CurrentUserAvatarController(),
          showLogoutAction: showLogoutAction,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Pushes EditProfileScreen on top of a stand-in "Home" screen, the way it
  // is really reached, so tests can assert on real navigation: popping back
  // to the previous screen, or — for logout — that the whole stack beneath
  // it is removed rather than just this one route.
  Future<void> pumpPushedEditProfile(
    WidgetTester tester, {
    FakeProfileService? service,
    FakeLogoutService? logoutService,
    CurrentUserAvatarController? avatarController,
    bool showLogoutAction = false,
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
                      logoutService: logoutService ?? FakeLogoutService(),
                      avatarController:
                          avatarController ?? CurrentUserAvatarController(),
                      showLogoutAction: showLogoutAction,
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
    final cameraButton = find.byKey(
      const ValueKey('edit-profile-camera-button'),
    );
    final sourceCameraOption = find.byKey(
      const ValueKey('edit-profile-avatar-source-camera'),
    );
    final sourceGalleryOption = find.byKey(
      const ValueKey('edit-profile-avatar-source-gallery'),
    );
    final sourceCancelOption = find.byKey(
      const ValueKey('edit-profile-avatar-source-cancel'),
    );
    final previewDialog = find.byKey(
      const ValueKey('edit-profile-avatar-preview-dialog'),
    );
    final previewUsePhoto = find.byKey(
      const ValueKey('edit-profile-avatar-preview-use-photo'),
    );
    final previewChooseAgain = find.byKey(
      const ValueKey('edit-profile-avatar-preview-choose-again'),
    );
    final previewCancel = find.byKey(
      const ValueKey('edit-profile-avatar-preview-cancel'),
    );

    bool avatarShowsImage(WidgetTester tester) {
      final container = tester.widget<Container>(
        find.byKey(const ValueKey('edit-profile-avatar')),
      );
      return container.child is Image;
    }

    testWidgets('Shows the avatar and camera/edit overlay', (tester) async {
      await pumpEditProfile(tester);

      expect(find.byKey(const ValueKey('edit-profile-avatar')), findsOneWidget);
      expect(cameraButton, findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(avatarShowsImage(tester), isFalse);
    });

    group('Source selection', () {
      testWidgets('Tapping the camera button opens the source selector', (
        tester,
      ) async {
        await pumpEditProfile(tester);

        await tester.tap(cameraButton);
        await tester.pumpAndSettle();

        expect(find.text('Take Photo'), findsOneWidget);
        expect(find.text('Choose from Gallery'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      });

      testWidgets(
        'Cancelling the source selector changes nothing and re-enables the '
        'camera button',
        (tester) async {
          final picker = FakeAvatarPickerService();
          await pumpEditProfile(tester, avatarPickerService: picker);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceCancelOption);
          await tester.pumpAndSettle();

          expect(picker.requestedSources, isEmpty);
          expect(avatarShowsImage(tester), isFalse);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );

      testWidgets(
        'Dismissing the source selector by tapping the barrier changes '
        'nothing',
        (tester) async {
          final picker = FakeAvatarPickerService();
          await pumpEditProfile(tester, avatarPickerService: picker);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          // Tap outside the sheet to dismiss it via the modal barrier.
          await tester.tapAt(const Offset(20, 20));
          await tester.pumpAndSettle();

          expect(picker.requestedSources, isEmpty);
          expect(avatarShowsImage(tester), isFalse);
        },
      );

      testWidgets(
        'Camera option requests camera permission and invokes the picker '
        'with the camera source',
        (tester) async {
          final permission = FakeAvatarPermissionService();
          final picker = FakeAvatarPickerService();
          await pumpEditProfile(
            tester,
            avatarPermissionService: permission,
            avatarPickerService: picker,
          );

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceCameraOption);
          await tester.pumpAndSettle();

          expect(permission.cameraRequestCount, 1);
          expect(permission.galleryRequestCount, 0);
          expect(picker.requestedSources, [AvatarImageSource.camera]);
        },
      );

      testWidgets(
        'Gallery option requests gallery permission and invokes the picker '
        'with the gallery source',
        (tester) async {
          final permission = FakeAvatarPermissionService();
          final picker = FakeAvatarPickerService();
          await pumpEditProfile(
            tester,
            avatarPermissionService: permission,
            avatarPickerService: picker,
          );

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();

          expect(permission.galleryRequestCount, 1);
          expect(permission.cameraRequestCount, 0);
          expect(picker.requestedSources, [AvatarImageSource.gallery]);
        },
      );

      testWidgets(
        'Cancelling the platform picker (returns null) changes nothing',
        (tester) async {
          final picker = FakeAvatarPickerService(cancelled: true);
          await pumpEditProfile(tester, avatarPickerService: picker);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();

          expect(picker.requestedSources, hasLength(1));
          expect(previewDialog, findsNothing);
          expect(avatarShowsImage(tester), isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    });

    group('Permissions', () {
      testWidgets('Denied camera permission shows feedback and does not '
          'open the picker', (tester) async {
        final permission = FakeAvatarPermissionService(
          cameraStatus: AvatarPermissionStatus.denied,
        );
        final picker = FakeAvatarPickerService();
        await pumpEditProfile(
          tester,
          avatarPermissionService: permission,
          avatarPickerService: picker,
        );

        await tester.tap(cameraButton);
        await tester.pumpAndSettle();
        await tester.tap(sourceCameraOption);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Camera access is needed to take a photo. Please allow '
            'access and try again.',
          ),
          findsOneWidget,
        );
        expect(picker.requestedSources, isEmpty);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets(
        'Permanently denied gallery permission shows feedback with an Open '
        'Settings action',
        (tester) async {
          final permission = FakeAvatarPermissionService(
            galleryStatus: AvatarPermissionStatus.permanentlyDenied,
          );
          await pumpEditProfile(tester, avatarPermissionService: permission);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();

          expect(find.text('Open Settings'), findsOneWidget);
          await tester.tap(find.text('Open Settings'));
          await tester.pumpAndSettle();

          expect(permission.openSettingsCallCount, 1);
        },
      );

      testWidgets('Does not repeatedly trigger the permission prompt from a '
          'single tap', (tester) async {
        final permission = FakeAvatarPermissionService(
          cameraStatus: AvatarPermissionStatus.denied,
        );
        await pumpEditProfile(tester, avatarPermissionService: permission);

        await tester.tap(cameraButton);
        await tester.pumpAndSettle();
        await tester.tap(sourceCameraOption);
        await tester.pumpAndSettle();

        expect(permission.cameraRequestCount, 1);
      });
    });

    group('Validation', () {
      testWidgets(
        'Invalid/unreadable image shows the validator message and does not '
        'proceed to cropping',
        (tester) async {
          final picker = FakeAvatarPickerService(
            resultPath: '/tmp/not-an-image.txt',
          );
          final processor = FakeAvatarImageProcessor(
            throwError: const AvatarImageValidationException(
              'Please choose a JPG, PNG, or HEIC photo.',
            ),
          );
          final cropper = FakeAvatarCropperService();
          await pumpEditProfile(
            tester,
            avatarPickerService: picker,
            avatarImageProcessor: processor,
            avatarCropperService: cropper,
          );

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();

          expect(
            find.text('Please choose a JPG, PNG, or HEIC photo.'),
            findsOneWidget,
          );
          expect(cropper.croppedSourcePaths, isEmpty);
          expect(avatarShowsImage(tester), isFalse);
        },
      );

      testWidgets('Picker failure shows feedback instead of crashing', (
        tester,
      ) async {
        final picker = FakeAvatarPickerService(
          throwError: Exception('picker exploded'),
        );
        await pumpEditProfile(tester, avatarPickerService: picker);

        await tester.tap(cameraButton);
        await tester.pumpAndSettle();
        await tester.tap(sourceGalleryOption);
        await tester.pumpAndSettle();

        expect(
          find.text("We couldn't open the picker. Please try again."),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('Crop and preview', () {
      Future<void> pickThroughToPreview(WidgetTester tester) async {
        await tester.tap(cameraButton);
        await tester.pumpAndSettle();
        await tester.tap(sourceGalleryOption);
        await tester.pumpAndSettle();
      }

      testWidgets('The selected image is passed to the cropper', (
        tester,
      ) async {
        final picker = FakeAvatarPickerService(resultPath: '/tmp/picked.jpg');
        final cropper = FakeAvatarCropperService();
        await pumpEditProfile(
          tester,
          avatarPickerService: picker,
          avatarCropperService: cropper,
        );

        await pickThroughToPreview(tester);

        expect(cropper.croppedSourcePaths, ['/tmp/picked.jpg']);
      });

      testWidgets('Cropper failure shows feedback and preserves the '
          'previous avatar', (tester) async {
        final cropper = FakeAvatarCropperService(
          throwError: Exception('crop failed'),
        );
        await pumpEditProfile(tester, avatarCropperService: cropper);

        await pickThroughToPreview(tester);

        expect(
          find.text("We couldn't crop that photo. Please try again."),
          findsOneWidget,
        );
        expect(previewDialog, findsNothing);
        expect(avatarShowsImage(tester), isFalse);
      });

      testWidgets('Cancelling cropping (returns null) preserves the '
          'previous avatar', (tester) async {
        final cropper = FakeAvatarCropperService(cancelled: true);
        await pumpEditProfile(tester, avatarCropperService: cropper);

        await pickThroughToPreview(tester);

        expect(previewDialog, findsNothing);
        expect(avatarShowsImage(tester), isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('The cropped image is shown in a preview with Use Photo, '
          'Choose Again, and Cancel actions', (tester) async {
        await pumpEditProfile(tester);

        await pickThroughToPreview(tester);

        expect(previewDialog, findsOneWidget);
        expect(
          find.byKey(const ValueKey('edit-profile-avatar-preview-image')),
          findsOneWidget,
        );
        expect(previewUsePhoto, findsOneWidget);
        expect(previewChooseAgain, findsOneWidget);
        expect(previewCancel, findsOneWidget);
      });

      testWidgets('Cancelling the preview preserves the previous avatar', (
        tester,
      ) async {
        final uploadService = FakeAvatarUploadService();
        await pumpEditProfile(tester, avatarUploadService: uploadService);

        await pickThroughToPreview(tester);
        await tester.tap(previewCancel);
        await tester.pumpAndSettle();

        expect(uploadService.submittedPaths, isEmpty);
        expect(avatarShowsImage(tester), isFalse);
      });

      testWidgets('Choose Again returns to source selection instead of '
          'confirming the current crop', (tester) async {
        final uploadService = FakeAvatarUploadService();
        await pumpEditProfile(tester, avatarUploadService: uploadService);

        await pickThroughToPreview(tester);
        await tester.tap(previewChooseAgain);
        await tester.pumpAndSettle();

        expect(find.text('Take Photo'), findsOneWidget);
        expect(uploadService.submittedPaths, isEmpty);

        await tester.tap(sourceCancelOption);
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets('Confirming the preview (Use Photo) invokes the avatar '
          'service exactly once', (tester) async {
        final uploadService = FakeAvatarUploadService();
        await pumpEditProfile(tester, avatarUploadService: uploadService);

        await pickThroughToPreview(tester);
        await tester.tap(previewUsePhoto);
        await tester.pumpAndSettle();

        expect(uploadService.submittedPaths, hasLength(1));
      });
    });

    group('Loading and duplicate actions', () {
      testWidgets(
        'Shows a loading indicator in place of the camera icon while an '
        'operation is in progress',
        (tester) async {
          final pending = Completer<PickedAvatarImage?>();
          final picker = FakeAvatarPickerService(pending: pending);
          await pumpEditProfile(tester, avatarPickerService: picker);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          // A duration well past the sheet's dismiss transition (not a
          // bare pump()), plus a trailing pump for the post-animation
          // route-removal callback, so the picker's pending future is
          // actually reached before asserting on the loading state.
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();

          // Scoped to the camera button itself: the sheet's "Take Photo"
          // option uses the same camera_alt_rounded icon, and may still be
          // completing its own dismiss animation at this point.
          expect(
            find.descendant(
              of: cameraButton,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: cameraButton,
              matching: find.byIcon(Icons.camera_alt_rounded),
            ),
            findsNothing,
          );

          pending.complete(null);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: cameraButton,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: cameraButton,
              matching: find.byIcon(Icons.camera_alt_rounded),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'The camera button is disabled (and a second picker call is not '
        'made) while an operation is in progress',
        (tester) async {
          final pending = Completer<PickedAvatarImage?>();
          final picker = FakeAvatarPickerService(pending: pending);
          await pumpEditProfile(tester, avatarPickerService: picker);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          expect(picker.requestedSources, hasLength(1));

          // The camera button's onTap is null while an operation is
          // active, so a second tap must be a no-op rather than opening a
          // second source sheet or invoking the picker again.
          final gestureDetector = tester.widget<GestureDetector>(cameraButton);
          expect(gestureDetector.onTap, isNull);

          await tester.tap(cameraButton);
          await tester.pump();

          expect(picker.requestedSources, hasLength(1));

          pending.complete(null);
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'Shows a loading indicator while the confirmed photo is being '
        'applied, then clears it',
        (tester) async {
          final pending = Completer<AvatarUpdateResult>();
          final uploadService = FakeAvatarUploadService(pending: pending);
          await pumpEditProfile(tester, avatarUploadService: uploadService);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();
          await tester.tap(previewUsePhoto);
          // A duration (not a bare pump()) so the dialog's dismiss
          // transition finishes and the upload service's pending future is
          // actually reached before asserting on the loading state.
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(CircularProgressIndicator), findsOneWidget);

          pending.complete(
            const AvatarUpdateResult(
              AvatarUpdateOutcome.success,
              localPath: '/tmp/stable/current_avatar.jpg',
              isLocalOnly: true,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );
    });

    group('Success', () {
      testWidgets(
        'A successful update replaces the Profile avatar with the stored '
        'image',
        (tester) async {
          await pumpEditProfile(tester);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();
          await tester.tap(previewUsePhoto);
          await tester.pumpAndSettle();

          expect(avatarShowsImage(tester), isTrue);
        },
      );

      testWidgets(
        'Shows local-only success feedback, never claiming a server upload',
        (tester) async {
          await pumpEditProfile(tester);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();
          await tester.tap(previewUsePhoto);
          await tester.pumpAndSettle();

          expect(
            find.text('Profile photo updated on this device.'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'A successful avatar update does not mark the text form as dirty '
        'or touch the Save Changes button',
        (tester) async {
          final profileService = FakeProfileService();
          await pumpEditProfile(tester, service: profileService);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();
          await tester.tap(previewUsePhoto);
          await tester.pumpAndSettle();

          expect(
            fieldText(tester, const ValueKey('edit-profile-full-name-field')),
            kMockUserProfile.fullName,
          );
          expect(profileService.submittedRequests, isEmpty);

          // Save Changes must still be disabled: nothing text-related
          // changed.
          await tester.ensureVisible(
            find.byKey(const ValueKey('edit-profile-save-button')),
          );
          await tester.tap(
            find.byKey(const ValueKey('edit-profile-save-button')),
          );
          await tester.pumpAndSettle();
          expect(profileService.submittedRequests, isEmpty);
        },
      );
    });

    group('Upload/service failure', () {
      testWidgets(
        'Shows feedback and preserves the previous avatar when the avatar '
        'service fails',
        (tester) async {
          final uploadService = FakeAvatarUploadService(
            result: const AvatarUpdateResult(
              AvatarUpdateOutcome.failure,
              message: "We couldn't update your photo. Please try again.",
            ),
          );
          await pumpEditProfile(tester, avatarUploadService: uploadService);

          await tester.tap(cameraButton);
          await tester.pumpAndSettle();
          await tester.tap(sourceGalleryOption);
          await tester.pumpAndSettle();
          await tester.tap(previewUsePhoto);
          await tester.pumpAndSettle();

          expect(
            find.text("We couldn't update your photo. Please try again."),
            findsOneWidget,
          );
          expect(avatarShowsImage(tester), isFalse);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );

      testWidgets('Shows a generic error message, not a crash, when the avatar '
          'service throws', (tester) async {
        final uploadService = FakeAvatarUploadService(
          result: Exception('boom'),
        );
        await pumpEditProfile(tester, avatarUploadService: uploadService);

        await tester.tap(cameraButton);
        await tester.pumpAndSettle();
        await tester.tap(sourceGalleryOption);
        await tester.pumpAndSettle();
        await tester.tap(previewUsePhoto);
        await tester.pumpAndSettle();

        expect(
          find.text("We couldn't update your photo. Please try again."),
          findsOneWidget,
        );
        expect(avatarShowsImage(tester), isFalse);
        expect(tester.takeException(), isNull);
      });
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

  group('Logout (hidden per approved Figma)', () {
    // The approved Edit Profile Figma has no Logout button, row, or menu
    // entry. The implementation (LogoutService plumbing, _handleLogout,
    // and _buildLogoutButton in edit_profile_screen.dart) is preserved
    // behind EditProfileScreen.showLogoutAction, which defaults to false
    // in every production call site, for later restoration; these tests
    // assert only on what's currently rendered by default. See the
    // "Logout (test-only visibility seam enabled)" group below for tests
    // of the already-implemented logout behavior itself.
    testWidgets('No Logout button, text, or key is rendered', (tester) async {
      await pumpEditProfile(tester);

      expect(find.text('Logout'), findsNothing);
      expect(
        find.byKey(const ValueKey('edit-profile-logout-button')),
        findsNothing,
      );
    });

    testWidgets(
      'The three-dot icon stays non-interactive and reveals no Logout entry',
      (tester) async {
        await pumpEditProfile(tester);

        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Logout'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Nothing renders below Save Changes other than the bottom navigation',
      (tester) async {
        await pumpEditProfile(tester);

        expect(
          find.byKey(const ValueKey('edit-profile-save-button')),
          findsOneWidget,
        );
        expect(find.byType(CustomBottomNav), findsOneWidget);
        expect(find.text('Logout'), findsNothing);
      },
    );
  });

  group('Logout (test-only visibility seam enabled)', () {
    // Exercises the already-implemented logout behavior via
    // EditProfileScreen.showLogoutAction: true — a @visibleForTesting-only
    // constructor parameter that defaults to false in every production
    // call site (see the group above, which is unaffected by these
    // tests). Never contacts real secure storage or the live API — only
    // FakeLogoutService, which stands in for AuthService.logout() (see
    // auth_service_test.dart's "logout" group for the real remote+local
    // orchestration this fake represents).
    const logoutButton = ValueKey('edit-profile-logout-button');

    testWidgets('the Logout action renders only when the seam is enabled', (
      tester,
    ) async {
      await pumpEditProfile(tester, showLogoutAction: true);

      expect(find.byKey(logoutButton), findsOneWidget);
    });

    group('successful logout', () {
      testWidgets('one tap calls LogoutService.logout exactly once', (
        tester,
      ) async {
        final logoutService = FakeLogoutService();
        await pumpPushedEditProfile(
          tester,
          logoutService: logoutService,
          showLogoutAction: true,
        );

        await tester.ensureVisible(find.byKey(logoutButton));
        await tester.tap(find.byKey(logoutButton));
        await tester.pumpAndSettle();

        expect(logoutService.logoutCallCount, 1);
      });

      testWidgets('duplicate taps while pending call logout only once', (
        tester,
      ) async {
        final completer = Completer<void>();
        final logoutService = FakeLogoutService(pending: completer);
        await pumpPushedEditProfile(
          tester,
          logoutService: logoutService,
          showLogoutAction: true,
        );

        await tester.ensureVisible(find.byKey(logoutButton));
        await tester.tap(find.byKey(logoutButton));
        await tester.pump();

        // Duplicate tap while pending — the button is already visible
        // from above, so no further scrolling is needed.
        await tester.tap(find.byKey(logoutButton));
        await tester.pump();
        expect(logoutService.logoutCallCount, 1);

        completer.complete();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('shows a loading state while pending, and the avatar is not '
          'cleared until it completes', (tester) async {
        final completer = Completer<void>();
        final logoutService = FakeLogoutService(pending: completer);
        final avatarController = CurrentUserAvatarController();
        await avatarController.setAvatarPath('/fake/path/avatar.png');
        await pumpPushedEditProfile(
          tester,
          logoutService: logoutService,
          avatarController: avatarController,
          showLogoutAction: true,
        );

        await tester.ensureVisible(find.byKey(logoutButton));
        await tester.tap(find.byKey(logoutButton));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(avatarController.avatarFile, isNotNull);

        completer.complete();
        // Bounded pumps through the pushAndRemoveUntil transition,
        // rather than pumpAndSettle: the outgoing route still paints
        // this screen's indeterminate CircularProgressIndicator for the
        // remainder of the transition, and an indeterminate animation
        // never lets pumpAndSettle observe "no more frames scheduled".
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(avatarController.avatarFile, isNull);
      });

      testWidgets('navigates with full-stack removal: Login is shown and Back '
          'cannot return to Profile or Home', (tester) async {
        final logoutService = FakeLogoutService();
        await pumpPushedEditProfile(
          tester,
          logoutService: logoutService,
          showLogoutAction: true,
        );

        await tester.ensureVisible(find.byKey(logoutButton));
        await tester.tap(find.byKey(logoutButton));
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(EditProfileScreen), findsNothing);
        expect(find.text('Open Edit Profile'), findsNothing);

        await tester.tap(find.text('BACK'));
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
      });

      testWidgets(
        'a remote HTTP 502 during AuthService.logout() (represented here by '
        'a LogoutService that still completes normally, per the '
        'remote-failure-still-clears-locally contract) still navigates to '
        'Login with the stack fully removed',
        (tester) async {
          // AuthService.logout() never rethrows a remote/transport failure
          // (see auth_service_test.dart's "remote 502 still clears locally"
          // coverage) — from EditProfileScreen's perspective, a logout
          // whose remote leg hit 502 is indistinguishable from one whose
          // remote leg hit 200: both are a LogoutService.logout() call that
          // simply completes. This fake represents that "502, but still
          // locally successful" outcome.
          final logoutService = FakeLogoutService();
          await pumpPushedEditProfile(
            tester,
            logoutService: logoutService,
            showLogoutAction: true,
          );

          await tester.ensureVisible(find.byKey(logoutButton));
          await tester.tap(find.byKey(logoutButton));
          await tester.pumpAndSettle();

          expect(logoutService.logoutCallCount, 1);
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(find.byType(EditProfileScreen), findsNothing);

          await tester.tap(find.text('BACK'));
          await tester.pumpAndSettle();

          expect(find.byType(LoginScreen), findsOneWidget);
        },
      );
    });

    group('expected secure logout failure', () {
      testWidgets(
        'remains on Profile, leaves the avatar untouched, resets loading, '
        'shows a neutral message, and does not navigate',
        (tester) async {
          final logoutService = FakeLogoutService(
            error: const SessionStorageException(SessionStorageOperation.clear),
          );
          final avatarController = CurrentUserAvatarController();
          await avatarController.setAvatarPath('/fake/path/avatar.png');
          await pumpPushedEditProfile(
            tester,
            logoutService: logoutService,
            avatarController: avatarController,
            showLogoutAction: true,
          );

          await tester.ensureVisible(find.byKey(logoutButton));
          await tester.tap(find.byKey(logoutButton));
          await tester.pumpAndSettle();

          expect(find.byType(EditProfileScreen), findsOneWidget);
          expect(find.byType(LoginScreen), findsNothing);
          expect(avatarController.avatarFile, isNotNull);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            find.text('Unable to sign out securely. Please try again.'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'a second tap after the loading state resets calls logout again '
        '(no confirmation dialog blocks the retry)',
        (tester) async {
          final logoutService = FakeLogoutService(
            error: const SessionStorageException(SessionStorageOperation.clear),
          );
          await pumpPushedEditProfile(
            tester,
            logoutService: logoutService,
            showLogoutAction: true,
          );

          await tester.ensureVisible(find.byKey(logoutButton));
          await tester.tap(find.byKey(logoutButton));
          await tester.pumpAndSettle();
          expect(logoutService.logoutCallCount, 1);

          logoutService.error = null;
          await tester.tap(find.byKey(logoutButton));
          await tester.pumpAndSettle();

          expect(logoutService.logoutCallCount, 2);
          expect(find.byType(LoginScreen), findsOneWidget);
        },
      );
    });

    group('programming-error boundary', () {
      testWidgets('a StateError from logout() is not relabeled as the neutral '
          'secure-logout failure', (tester) async {
        final logoutService = FakeLogoutService(
          error: StateError('simulated programmer error'),
        );
        await pumpPushedEditProfile(
          tester,
          logoutService: logoutService,
          showLogoutAction: true,
        );

        // Invokes the button's onTap directly rather than through
        // tester.tap(): FakeLogoutService.logout's synchronous throw (no
        // pending gate) makes _handleLogout's returned Future reject
        // within the same dispatch, and flutter_test's gesture
        // simulation cannot be wrapped in expectLater around an
        // in-flight unhandled async error without a guard conflict.
        // onTap's static type is `void Function()` (Dart's void-
        // covariance lets an async handler satisfy it), but the actual
        // runtime value returned is still the real Future<void> —
        // captured here via `dynamic` so it can be awaited directly, a
        // deterministic mechanism for observing that this programming
        // defect is not silently converted into the neutral
        // secure-logout-failure message.
        final inkWell = tester.widget<InkWell>(find.byKey(logoutButton));
        final Function onTap = inkWell.onTap!;
        final dynamic pendingLogout = onTap();

        await expectLater(pendingLogout, throwsA(isA<StateError>()));

        expect(
          find.text('Unable to sign out securely. Please try again.'),
          findsNothing,
        );
      });
    });

    testWidgets(
      'no confirmation dialog appears before or after tapping Logout',
      (tester) async {
        final logoutService = FakeLogoutService();
        await pumpPushedEditProfile(
          tester,
          logoutService: logoutService,
          showLogoutAction: true,
        );

        await tester.ensureVisible(find.byKey(logoutButton));
        await tester.tap(find.byKey(logoutButton));
        await tester.pump();

        expect(find.byType(AlertDialog), findsNothing);

        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
      },
    );
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
    testWidgets('Can scroll to the Save Changes button without overflow', (
      tester,
    ) async {
      await pumpEditProfile(tester, width: 320, height: 560);

      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit-profile-save-button')),
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
