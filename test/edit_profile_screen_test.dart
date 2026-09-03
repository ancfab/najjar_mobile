// Widget checks for the Edit Profile screen: header/back button, avatar +
// camera overlay, client info, prefilled form fields (including multiline
// Business Address), Save Changes submission against a fake in-memory
// service, Logout, bottom navigation (Profile selected), responsive/overflow
// safety, and real back navigation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/config/api_config.dart';
import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/screens/change_password_screen.dart';
import 'package:anc_fabrics/screens/edit_profile_screen.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/screens/orders_screen.dart';
import 'package:anc_fabrics/screens/support_screen.dart';
import 'package:anc_fabrics/models/local_customer_profile.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/avatar_image_processor.dart';
import 'package:anc_fabrics/services/avatar_permission_service.dart';
import 'package:anc_fabrics/services/avatar_picker_service.dart';
import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/services/local_customer_profile_store.dart';
import 'package:anc_fabrics/services/profile_service.dart';
import 'package:anc_fabrics/services/session_storage_exception.dart';
import 'package:anc_fabrics/widgets/custom_bottom_nav.dart';

import 'helpers/fake_auth_session_store.dart';
import 'helpers/fake_avatar_cropper_service.dart';
import 'helpers/fake_avatar_image_processor.dart';
import 'helpers/fake_avatar_permission_service.dart';
import 'helpers/fake_avatar_picker_service.dart';
import 'helpers/fake_local_customer_profile_store.dart';
import 'helpers/fake_logout_service.dart';
import 'helpers/fake_profile_service.dart';
import 'helpers/recording_multipart_http_client.dart';
import 'helpers/valid_avatar_image.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

AuthSession _defaultIdentitySession() => const AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: 'sample.user',
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

/// An http.Client that fails the test if it is ever called — the default
/// for tests that don't exercise the real identity/avatar network flow, so
/// an accidental unwanted call is caught immediately rather than silently
/// hanging or returning an unrelated canned response.
class _ShouldNeverBeCalledHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError(
      'AuthService must not call the ANC API in this test — no '
      'identity/avatar flow is under test here.',
    );
  }

  @override
  void close() {}
}

/// Builds a real [AuthService] over [httpClient] (defaulting to one that
/// fails the test if ever called) and a [FakeAuthSessionStore] seeded with
/// [session] (defaulting to [_defaultIdentitySession]) — the same
/// real-service-over-fake-transport pattern used throughout
/// auth_service_test.dart, so EditProfileScreen's real
/// updateProfile/uploadAvatar/currentSession calls are exercised for real,
/// never re-implemented as a parallel fake.
AuthService _authServiceFor({http.Client? httpClient, AuthSession? session}) {
  final store = FakeAuthSessionStore()
    ..seed(session ?? _defaultIdentitySession());
  return AuthService(
    apiClient: AncApiClient(
      httpClient: httpClient ?? _ShouldNeverBeCalledHttpClient(),
    ),
    sessionStore: store,
  );
}

/// Records the single plain (non-multipart) request it receives and
/// replies with a canned response — for `PATCH /auth/me` calls
/// (`AuthService.updateProfile`), which never use multipart. Mirrors the
/// fixture in auth_service_test.dart.
class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  http.Request? lastRequest;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    lastRequest = req;
    requestCount++;
    return _respond(req);
  }

  @override
  void close() {}
}

http.StreamedResponse _jsonResponse(
  int statusCode,
  Map<String, dynamic> body, {
  required http.Request request,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

/// Default `PATCH /auth/me` success-response user body, matching
/// [_defaultIdentitySession]'s fields — [username]/[phone] overridable to
/// simulate the field(s) that were actually changed.
Map<String, dynamic> updateMeUserJson({
  String username = 'sample.user',
  String phone = '+96890000000',
}) => {
  'id': 7,
  'username': username,
  'phone': phone,
  'country': 'OM',
  'client_id': ApiConfig.clientId,
  'bc_customer_no': 'SAMPLE-0001',
  'must_change_password': false,
};

/// A [LocalCustomerProfileStore] whose [load] always throws, simulating a
/// misbehaving implementation (the real [SecureLocalCustomerProfileStore]
/// never throws from [load] — see its doc comment) so this screen's own
/// defensive handling (falling back to the mock defaults instead of
/// crashing) is verified independently of that guarantee.
class _ThrowingLoadLocalCustomerProfileStore
    implements LocalCustomerProfileStore {
  @override
  Future<LocalCustomerProfile?> load(int userId) async {
    throw Exception('local profile store unavailable');
  }

  @override
  Future<void> save(int userId, LocalCustomerProfile profile) async {}

  @override
  Future<void> clear(int userId) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpEditProfile(
    WidgetTester tester, {
    double width = 390,
    double height = 800,
    FakeProfileService? service,
    FakeLogoutService? logoutService,
    AuthService? authService,
    LocalCustomerProfileStore? localProfileStore,
    FakeAvatarPickerService? avatarPickerService,
    FakeAvatarPermissionService? avatarPermissionService,
    FakeAvatarCropperService? avatarCropperService,
    FakeAvatarImageProcessor? avatarImageProcessor,
    CurrentUserAvatarController? avatarController,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: EditProfileScreen(
          service: service ?? FakeProfileService(),
          logoutService: logoutService ?? FakeLogoutService(),
          authService: authService ?? _authServiceFor(),
          localProfileStore:
              localProfileStore ?? FakeLocalCustomerProfileStore(),
          avatarPickerService: avatarPickerService ?? FakeAvatarPickerService(),
          avatarPermissionService:
              avatarPermissionService ?? FakeAvatarPermissionService(),
          avatarCropperService:
              avatarCropperService ?? FakeAvatarCropperService(),
          avatarImageProcessor:
              avatarImageProcessor ?? FakeAvatarImageProcessor(),
          avatarController: avatarController ?? CurrentUserAvatarController(),
        ),
      ),
    );
    // The screen's own async identity prefill (AuthService.currentSession,
    // a local secure-storage read with no network call) needs one extra
    // pump beyond pumpAndSettle's own frame-scheduling wait, since it's
    // driven by a plain awaited Future, not an animation.
    await tester.pumpAndSettle();
    await tester.pump();
  }

  // Pushes EditProfileScreen on top of a stand-in "Home" screen, the way it
  // is really reached, so tests can assert on real navigation: popping back
  // to the previous screen, or — for logout — that the whole stack beneath
  // it is removed rather than just this one route.
  Future<void> pumpPushedEditProfile(
    WidgetTester tester, {
    FakeProfileService? service,
    FakeLogoutService? logoutService,
    AuthService? authService,
    LocalCustomerProfileStore? localProfileStore,
    CurrentUserAvatarController? avatarController,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(
                      service: service ?? FakeProfileService(),
                      logoutService: logoutService ?? FakeLogoutService(),
                      authService: authService ?? _authServiceFor(),
                      localProfileStore:
                          localProfileStore ?? FakeLocalCustomerProfileStore(),
                      avatarController:
                          avatarController ?? CurrentUserAvatarController(),
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
    await tester.pump();

    await tester.tap(find.text('Open Edit Profile'));
    await tester.pumpAndSettle();
    await tester.pump();
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

    // The cropper echoes the picker's resultPath through unchanged by
    // default, and AuthService.uploadAvatar checks the file actually
    // exists/reads its bytes before ever making a network call — so any
    // test that reaches "Use Photo" needs a real file on disk (the default
    // /tmp/fake_picked_avatar.jpg placeholder path is not enough).
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'edit_profile_avatar_test',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<String> writeRealAvatarFile({List<int>? bytes}) async {
      final file = File('${tempDir.path}/cropped_avatar.jpg');
      await file.writeAsBytes(bytes ?? validAvatarPngBytes);
      return file.path;
    }

    // Convenience wrapper: real dart:io file writes awaited directly in a
    // testWidgets body have been observed to hang (see
    // valid_avatar_image.dart's doc comment) — runAsync is the escape
    // hatch onto the real event loop for exactly this.
    Future<String> writeRealAvatarFileAsync(
      WidgetTester tester, {
      List<int>? bytes,
    }) async {
      late String path;
      await tester.runAsync(() async {
        path = await writeRealAvatarFile(bytes: bytes);
      });
      return path;
    }

    Map<String, dynamic> uploadedUserJson({
      // A loopback address with nothing listening refuses the connection
      // almost instantly, without a real DNS lookup or network round trip
      // — unlike a real internet host, which occasionally takes long
      // enough to resolve the NetworkImage's async failure after this
      // test has already ended, misattributing the error to whichever
      // test happens to be running next.
      String avatarUrl = 'http://127.0.0.1:9/avatars/7.jpg',
    }) => {
      'id': 7,
      'username': 'sample.user',
      'phone': '+96890000000',
      'country': 'OM',
      'client_id': ApiConfig.clientId,
      'bc_customer_no': 'SAMPLE-0001',
      'must_change_password': false,
      'avatar_url': avatarUrl,
    };

    // Runs the whole camera-tap-through-"Use Photo" flow inside one
    // tester.runAsync call. AuthService.uploadAvatar reads the confirmed
    // avatar from a real file on disk — genuine dart:io async work the
    // fake-async zone testWidgets normally runs in can never observe
    // completing (see valid_avatar_image.dart's doc comment) — and since
    // the whole pick→crop→preview→confirm chain is one continuous async
    // function starting at the camera-button tap (each `await`'s
    // continuation resumes in the zone captured when that chain started,
    // not whatever zone later re-enters it), the *entire* chain has to
    // run inside the same runAsync call, not just the final tap, for that
    // real read to actually complete. pumpAndSettle is safe for the first
    // two (finite, fake/instant) modal-entrance animations; it is
    // deliberately never used after the final tap — the camera button's
    // indeterminate loading spinner (shown while the upload is in flight)
    // never stops scheduling frames on its own, so pumpAndSettle would
    // never observe "settled" regardless of whether the upload itself has
    // finished, the same reasoning already documented elsewhere in this
    // file for the logout spinner. Bounded pumps instead.
    Future<void> confirmAvatarUpload(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(cameraButton);
        await tester.pumpAndSettle();
        await tester.tap(sourceGalleryOption);
        await tester.pumpAndSettle();
        await tester.tap(previewUsePhoto);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      });
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
              AvatarImageValidationReason.unsupportedFormat,
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
        final httpClient = RecordingMultipartHttpClient(
          (req) async => multipartJsonResponse(200, {
            'data': uploadedUserJson(),
          }, request: req),
        );
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(httpClient: httpClient),
        );

        await pickThroughToPreview(tester);
        await tester.tap(previewCancel);
        await tester.pumpAndSettle();

        expect(httpClient.lastRequest, isNull);
        expect(avatarShowsImage(tester), isFalse);
      });

      testWidgets('Choose Again returns to source selection instead of '
          'confirming the current crop', (tester) async {
        final httpClient = RecordingMultipartHttpClient(
          (req) async => multipartJsonResponse(200, {
            'data': uploadedUserJson(),
          }, request: req),
        );
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(httpClient: httpClient),
        );

        await pickThroughToPreview(tester);
        await tester.tap(previewChooseAgain);
        await tester.pumpAndSettle();

        expect(find.text('Take Photo'), findsOneWidget);
        expect(httpClient.lastRequest, isNull);

        await tester.tap(sourceCancelOption);
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets('Confirming the preview (Use Photo) invokes the avatar '
          'service exactly once, sending the file under the "avatar" field', (
        tester,
      ) async {
        final path = await writeRealAvatarFileAsync(tester);
        final picker = FakeAvatarPickerService(resultPath: path);
        final httpClient = RecordingMultipartHttpClient(
          (req) async => multipartJsonResponse(200, {
            'data': uploadedUserJson(),
          }, request: req),
        );
        await pumpEditProfile(
          tester,
          avatarPickerService: picker,
          authService: _authServiceFor(httpClient: httpClient),
        );

        await confirmAvatarUpload(tester);

        expect(httpClient.requestCount, 1);
        expect(httpClient.lastRequest!.method, 'POST');
        expect(httpClient.lastRequest!.files.single.field, 'avatar');
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
          final path = await writeRealAvatarFileAsync(tester);
          final picker = FakeAvatarPickerService(resultPath: path);
          final pending = Completer<http.StreamedResponse>();
          final httpClient = RecordingMultipartHttpClient(
            (req) => pending.future,
          );
          await pumpEditProfile(
            tester,
            avatarPickerService: picker,
            authService: _authServiceFor(httpClient: httpClient),
          );

          // The whole chain — including the real file read triggered by
          // tapping "Use Photo" — must run inside one runAsync call, or
          // the continuation resumes in the wrong (fake-async) zone and
          // never reaches the pending future.
          await tester.runAsync(() async {
            await tester.tap(cameraButton);
            await tester.pumpAndSettle();
            await tester.tap(sourceGalleryOption);
            await tester.pumpAndSettle();
            await tester.tap(previewUsePhoto);
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await tester.pump(const Duration(milliseconds: 300));

            expect(find.byType(CircularProgressIndicator), findsOneWidget);

            pending.complete(
              multipartJsonResponse(200, {
                'data': uploadedUserJson(),
              }, request: httpClient.lastRequest!),
            );
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
          });

          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );
    });

    group('Success', () {
      testWidgets(
        'A successful update replaces the Profile avatar with the returned '
        'avatar_url',
        (tester) async {
          final path = await writeRealAvatarFileAsync(tester);
          final picker = FakeAvatarPickerService(resultPath: path);
          final avatarController = CurrentUserAvatarController();
          final httpClient = RecordingMultipartHttpClient(
            (req) async => multipartJsonResponse(200, {
              'data': uploadedUserJson(),
            }, request: req),
          );
          await pumpEditProfile(
            tester,
            avatarPickerService: picker,
            avatarController: avatarController,
            authService: _authServiceFor(httpClient: httpClient),
          );

          await confirmAvatarUpload(tester);

          expect(avatarShowsImage(tester), isTrue);
          expect(
            avatarController.avatarUrl,
            'http://127.0.0.1:9/avatars/7.jpg',
          );
        },
      );

      testWidgets('Shows success feedback only after the server responds', (
        tester,
      ) async {
        final path = await writeRealAvatarFileAsync(tester);
        final picker = FakeAvatarPickerService(resultPath: path);
        final httpClient = RecordingMultipartHttpClient(
          (req) async => multipartJsonResponse(200, {
            'data': uploadedUserJson(),
          }, request: req),
        );
        await pumpEditProfile(
          tester,
          avatarPickerService: picker,
          authService: _authServiceFor(httpClient: httpClient),
        );

        await confirmAvatarUpload(tester);

        expect(find.text('Profile photo updated.'), findsOneWidget);
      });

      testWidgets(
        'A successful avatar update does not mark the text form as dirty '
        'or touch the Save Changes button',
        (tester) async {
          final path = await writeRealAvatarFileAsync(tester);
          final picker = FakeAvatarPickerService(resultPath: path);
          final profileService = FakeProfileService();
          final httpClient = RecordingMultipartHttpClient(
            (req) async => multipartJsonResponse(200, {
              'data': uploadedUserJson(),
            }, request: req),
          );
          await pumpEditProfile(
            tester,
            avatarPickerService: picker,
            service: profileService,
            authService: _authServiceFor(httpClient: httpClient),
          );

          await confirmAvatarUpload(tester);

          expect(
            fieldText(tester, const ValueKey('edit-profile-full-name-field')),
            '',
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
        'Shows feedback and preserves the previous avatar when the server '
        'rejects the upload',
        (tester) async {
          final path = await writeRealAvatarFileAsync(tester);
          final picker = FakeAvatarPickerService(resultPath: path);
          final httpClient = RecordingMultipartHttpClient(
            (req) async => multipartJsonResponse(422, {
              'errors': {
                'avatar': ["We couldn't update your photo. Please try again."],
              },
            }, request: req),
          );
          await pumpEditProfile(
            tester,
            avatarPickerService: picker,
            authService: _authServiceFor(httpClient: httpClient),
          );

          await confirmAvatarUpload(tester);

          expect(
            find.text("We couldn't update your photo. Please try again."),
            findsOneWidget,
          );
          expect(avatarShowsImage(tester), isFalse);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );

      testWidgets(
        'Shows a generic error message, not a crash, when the upload throws '
        'a transport failure',
        (tester) async {
          final path = await writeRealAvatarFileAsync(tester);
          final picker = FakeAvatarPickerService(resultPath: path);
          final httpClient = RecordingMultipartHttpClient(
            (req) async => throw const SocketException('No route to host'),
          );
          await pumpEditProfile(
            tester,
            avatarPickerService: picker,
            authService: _authServiceFor(httpClient: httpClient),
          );

          await confirmAvatarUpload(tester);

          expect(
            find.text("We couldn't update your photo. Please try again."),
            findsOneWidget,
          );
          expect(avatarShowsImage(tester), isFalse);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'A file exceeding 5 MB is rejected locally, without an API call',
        (tester) async {
          final oversizedPath = await writeRealAvatarFileAsync(
            tester,
            bytes: <int>[
              ...validAvatarPngBytes,
              ...List<int>.filled(
                ApiConfig.avatarMaxUploadBytes + 1 - validAvatarPngBytes.length,
                0,
              ),
            ],
          );
          final picker = FakeAvatarPickerService(resultPath: oversizedPath);
          final httpClient = RecordingMultipartHttpClient(
            (req) async => multipartJsonResponse(200, {
              'data': uploadedUserJson(),
            }, request: req),
          );
          await pumpEditProfile(
            tester,
            avatarPickerService: picker,
            authService: _authServiceFor(httpClient: httpClient),
          );

          await confirmAvatarUpload(tester);

          expect(
            find.text(
              'That photo is too large. Please choose a smaller image.',
            ),
            findsOneWidget,
          );
          expect(httpClient.lastRequest, isNull);
          expect(avatarShowsImage(tester), isFalse);
        },
      );
    });
  });

  group('Client info', () {
    testWidgets(
      "Shows the account's real BC customer number from the session",
      (tester) async {
        await pumpEditProfile(tester);
        await tester.pump();

        expect(find.text('ANC ID: #SAMPLE-0001'), findsOneWidget);
      },
    );

    testWidgets(
      'Shows no ANC ID label when the session has no linked BC customer',
      (tester) async {
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(
            session: const AuthSession(
              token: _syntheticToken,
              userId: 7,
              username: 'sample.user',
              phone: '+96890000000',
              country: 'OM',
              clientId: 'ANCNAJJAR',
              bcCustomerNo: null,
              mustChangePassword: false,
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('edit-profile-bc-customer-no')),
          findsNothing,
        );
      },
    );
  });

  group('Form fields', () {
    testWidgets(
      'The four locally-owned fields render empty when no local profile has '
      'been saved yet — never fabricated mock values',
      (tester) async {
        await pumpEditProfile(tester);

        expect(find.text('Full Name'), findsOneWidget);
        expect(find.text('Email Address'), findsOneWidget);
        expect(find.text('Company'), findsOneWidget);
        expect(find.text('Business Address'), findsOneWidget);

        expect(
          fieldText(tester, const ValueKey('edit-profile-full-name-field')),
          '',
        );
        expect(
          fieldText(tester, const ValueKey('edit-profile-email-field')),
          '',
        );
        expect(
          fieldText(tester, const ValueKey('edit-profile-company-field')),
          '',
        );
        expect(
          fieldText(
            tester,
            const ValueKey('edit-profile-business-address-field'),
          ),
          '',
        );
      },
    );

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

  group('Local customer profile persistence', () {
    const savedProfile = LocalCustomerProfile(
      fullName: 'Priya Natarajan',
      email: 'priya.n@example.com',
      company: 'Coastal Textiles LLC',
      businessAddress: '12 Harbor Road, Muscat',
    );

    testWidgets(
      'Loads a previously-saved local profile for the authenticated userId '
      'instead of the mock defaults',
      (tester) async {
        final localProfileStore = FakeLocalCustomerProfileStore()
          ..seed(_defaultIdentitySession().userId, savedProfile);
        await pumpEditProfile(tester, localProfileStore: localProfileStore);

        expect(
          fieldText(tester, const ValueKey('edit-profile-full-name-field')),
          savedProfile.fullName,
        );
        expect(
          fieldText(tester, const ValueKey('edit-profile-email-field')),
          savedProfile.email,
        );
        expect(
          fieldText(tester, const ValueKey('edit-profile-company-field')),
          savedProfile.company,
        );
        expect(
          fieldText(
            tester,
            const ValueKey('edit-profile-business-address-field'),
          ),
          savedProfile.businessAddress,
        );
      },
    );

    testWidgets(
      'A new account with no local profile yet starts with genuinely empty '
      'fields, and nothing is written back to the store on open',
      (tester) async {
        final localProfileStore = FakeLocalCustomerProfileStore();
        await pumpEditProfile(tester, localProfileStore: localProfileStore);

        expect(
          fieldText(tester, const ValueKey('edit-profile-full-name-field')),
          '',
        );
        expect(
          fieldText(tester, const ValueKey('edit-profile-email-field')),
          '',
        );
        expect(
          fieldText(tester, const ValueKey('edit-profile-company-field')),
          '',
        );
        expect(
          fieldText(
            tester,
            const ValueKey('edit-profile-business-address-field'),
          ),
          '',
        );
        expect(localProfileStore.savedUserIds, isEmpty);
      },
    );

    testWidgets('Saving persists the edited fields locally, keyed by the '
        'authenticated userId', (tester) async {
      final localProfileStore = FakeLocalCustomerProfileStore();
      await pumpEditProfile(tester, localProfileStore: localProfileStore);

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-full-name-field')),
        'Priya Natarajan',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      final saved = await localProfileStore.load(
        _defaultIdentitySession().userId,
      );
      expect(saved?.fullName, 'Priya Natarajan');
      // The other three fields were never touched, so they persist as the
      // genuinely empty values they started with — never a fabricated
      // mock value.
      expect(saved?.email, '');
      expect(saved?.company, '');
      expect(saved?.businessAddress, '');
    });

    testWidgets(
      'Saving persists locally even though ProfileService (no real backend '
      'yet) reports updates as not connected',
      (tester) async {
        final localProfileStore = FakeLocalCustomerProfileStore();
        await pumpEditProfile(
          tester,
          service: FakeProfileService(result: ProfileUpdateResult.unavailable),
          localProfileStore: localProfileStore,
        );

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
        final saved = await localProfileStore.load(
          _defaultIdentitySession().userId,
        );
        expect(saved?.company, 'Sterling Freight Co.');
      },
    );

    testWidgets(
      'Reopening the screen after a save shows the previously saved local '
      'values, not the mock defaults',
      (tester) async {
        final localProfileStore = FakeLocalCustomerProfileStore();
        await pumpEditProfile(tester, localProfileStore: localProfileStore);

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          'Priya Natarajan',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        // Simulates leaving and reopening Edit Profile: a fresh screen
        // instance backed by the same (persistent) local profile store.
        await pumpEditProfile(tester, localProfileStore: localProfileStore);

        expect(
          fieldText(tester, const ValueKey('edit-profile-full-name-field')),
          'Priya Natarajan',
        );
      },
    );

    testWidgets(
      'A local profile store that fails to load does not crash and leaves '
      'the fields empty (never falling back to fabricated mock data)',
      (tester) async {
        final localProfileStore = _ThrowingLoadLocalCustomerProfileStore();
        await pumpEditProfile(tester, localProfileStore: localProfileStore);

        expect(tester.takeException(), isNull);
        expect(
          fieldText(tester, const ValueKey('edit-profile-full-name-field')),
          '',
        );
      },
    );
  });

  group('Identity fields (username/phone)', () {
    testWidgets(
      'Username and phone are prepopulated from the authenticated session, '
      'with the dial code shown as a read-only prefix',
      (tester) async {
        await pumpEditProfile(tester);

        expect(find.text('Username'), findsOneWidget);
        expect(find.text('Phone Number'), findsOneWidget);
        expect(
          fieldText(tester, const ValueKey('edit-profile-username-field')),
          'sample.user',
        );
        // Local digits only — the +968 dial code (Oman, the default
        // session's country) is shown as a fixed prefix, not editable
        // text, and must never be duplicated into the field's own value.
        expect(
          fieldText(tester, const ValueKey('edit-profile-phone-field')),
          '90000000',
        );
        expect(find.textContaining('+968'), findsOneWidget);
      },
    );

    testWidgets(
      'A different session country renders that country\'s dial code and '
      'strips it from the displayed digits',
      (tester) async {
        const session = AuthSession(
          token: _syntheticToken,
          userId: 7,
          username: 'other.user',
          phone: '+96170123456',
          country: 'LB',
          clientId: 'ANCNAJJAR',
          bcCustomerNo: 'SAMPLE-0001',
          mustChangePassword: false,
        );
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(session: session),
        );

        expect(
          fieldText(tester, const ValueKey('edit-profile-phone-field')),
          '70123456',
        );
        expect(find.textContaining('+961'), findsOneWidget);
      },
    );

    testWidgets('No request occurs when neither username nor phone changed', (
      tester,
    ) async {
      final recorder = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, {'data': updateMeUserJson()}, request: req),
      );
      await pumpEditProfile(
        tester,
        authService: _authServiceFor(httpClient: recorder),
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(recorder.lastRequest, isNull);
    });

    testWidgets(
      'A username-only change sends only username to PATCH /auth/me',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _jsonResponse(200, {
            'data': updateMeUserJson(username: 'new.username'),
          }, request: req),
        );
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(httpClient: recorder),
        );

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-username-field')),
          'new.username',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(recorder.lastRequest!.method, 'PATCH');
        final sentBody =
            jsonDecode(recorder.lastRequest!.body) as Map<String, dynamic>;
        expect(sentBody, {'username': 'new.username'});
        expect(find.text('Profile updated.'), findsOneWidget);
      },
    );

    testWidgets('A phone-only change sends only phone (composed with the '
        'fixed dial code) to PATCH /auth/me', (tester) async {
      final recorder = _RecordingHttpClient(
        (req) async => _jsonResponse(200, {
          'data': updateMeUserJson(phone: '+96890009999'),
        }, request: req),
      );
      await pumpEditProfile(
        tester,
        authService: _authServiceFor(httpClient: recorder),
      );

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-phone-field')),
        '90009999',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      final sentBody =
          jsonDecode(recorder.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody, {'phone': '+96890009999'});
    });

    testWidgets('Both changed fields are sent together', (tester) async {
      final recorder = _RecordingHttpClient(
        (req) async => _jsonResponse(200, {
          'data': updateMeUserJson(
            username: 'new.username',
            phone: '+96890009999',
          ),
        }, request: req),
      );
      await pumpEditProfile(
        tester,
        authService: _authServiceFor(httpClient: recorder),
      );

      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-username-field')),
        'new.username',
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit-profile-phone-field')),
        '90009999',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      final sentBody =
          jsonDecode(recorder.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody, {'username': 'new.username', 'phone': '+96890009999'});
    });

    testWidgets(
      'Save is disabled while submitting and a duplicate tap sends only one '
      'request',
      (tester) async {
        final pending = Completer<http.StreamedResponse>();
        final recorder = _RecordingHttpClient((req) => pending.future);
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(httpClient: recorder),
        );

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-username-field')),
          'new.username',
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

        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pump();
        expect(recorder.requestCount, 1);

        pending.complete(
          _jsonResponse(200, {
            'data': updateMeUserJson(username: 'new.username'),
          }, request: recorder.lastRequest!),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'A taken-username failure shows an inline field error and preserves '
      'the typed value',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'errors': {
              'username': ['The username has already been taken.'],
            },
          }, request: req),
        );
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(httpClient: recorder),
        );

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-username-field')),
          'taken.username',
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
          find.text('The username has already been taken.'),
          findsOneWidget,
        );
        expect(
          fieldText(tester, const ValueKey('edit-profile-username-field')),
          'taken.username',
        );
      },
    );

    testWidgets(
      'An invalid-phone failure shows an inline field error and preserves '
      'the typed value',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'errors': {
              'phone': ['The phone has already been taken.'],
            },
          }, request: req),
        );
        await pumpEditProfile(
          tester,
          authService: _authServiceFor(httpClient: recorder),
        );

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-phone-field')),
          '90009999',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('The phone has already been taken.'), findsOneWidget);
        expect(
          fieldText(tester, const ValueKey('edit-profile-phone-field')),
          '90009999',
        );
      },
    );

    testWidgets(
      'HTTP 401 clears the avatar and navigates to Login with the stack '
      'removed',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _jsonResponse(401, const {}, request: req),
        );
        final avatarController = CurrentUserAvatarController();
        avatarController.setAvatarUrl('http://127.0.0.1:9/avatars/7.jpg');
        await pumpPushedEditProfile(
          tester,
          authService: _authServiceFor(httpClient: recorder),
          avatarController: avatarController,
        );

        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-username-field')),
          'new.username',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(avatarController.avatarUrl, isNull);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(EditProfileScreen), findsNothing);
      },
    );

    testWidgets('Managed fields (country, client_id, bc_customer_no) are never '
        'editable and never sent', (tester) async {
      // No dedicated country/client_id/bc_customer_no TextFormField
      // exists anywhere on this screen — the only country-related UI is
      // the phone field's fixed, non-interactive dial-code prefix.
      await pumpEditProfile(tester);

      expect(find.byType(TextFormField), findsNWidgets(6));
      expect(find.text('AE'), findsNothing);
      expect(find.text('OM'), findsNothing);
      expect(find.text('ANCNAJJAR'), findsNothing);
      expect(find.text('SAMPLE-0001'), findsNothing);
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
      // Untouched fields are submitted as the genuinely empty values they
      // started with — never a fabricated mock value. `phone` is the one
      // exception: it is not a locally-owned customer field, so it still
      // comes from widget.profile (see the class doc comment).
      expect(request.email, '');
      // Not a locally-owned customer field — it's re-composed from the
      // real, authenticated identity fields (dial code + phone digits),
      // never from any mock/fabricated value.
      expect(request.phone, '+96890000000');
      expect(request.company, '');
      expect(request.businessAddress, '');
    });

    testWidgets(
      'Trims leading/trailing whitespace before treating a field as changed',
      (tester) async {
        final service = FakeProfileService();
        await pumpEditProfile(tester, service: service);

        // Whitespace-only, which trims to '' — the field's empty baseline
        // (no local profile saved yet) — so this must not count as a
        // change.
        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-full-name-field')),
          '   ',
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
      'Full Name is optional — leaving it empty does not block submission '
      '(no local profile means it legitimately starts blank)',
      (tester) async {
        final service = FakeProfileService();
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

        expect(find.text('Please enter your full name.'), findsNothing);
        expect(service.submittedRequests, hasLength(1));
        expect(service.submittedRequests.single.fullName, '');
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
        // Restores to '' — the field's empty baseline (no local profile
        // saved yet).
        await tester.enterText(find.byKey(key), '');
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
    // Exercises the logout action, now rendered by default in production.
    // Never contacts real secure storage or the live API — only
    // FakeLogoutService, which stands in for AuthService.logout() (see
    // auth_service_test.dart's "logout" group for the real remote+local
    // orchestration this fake represents).
    const logoutButton = ValueKey('edit-profile-logout-button');

    testWidgets('the Logout action renders by default', (tester) async {
      await pumpEditProfile(tester);

      expect(find.byKey(logoutButton), findsOneWidget);
    });

    group('successful logout', () {
      testWidgets('one tap calls LogoutService.logout exactly once', (
        tester,
      ) async {
        final logoutService = FakeLogoutService();
        await pumpPushedEditProfile(tester, logoutService: logoutService);

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
        await pumpPushedEditProfile(tester, logoutService: logoutService);

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
        avatarController.setAvatarUrl('http://127.0.0.1:9/avatars/7.jpg');
        await pumpPushedEditProfile(
          tester,
          logoutService: logoutService,
          avatarController: avatarController,
        );

        await tester.ensureVisible(find.byKey(logoutButton));
        await tester.tap(find.byKey(logoutButton));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(avatarController.avatarUrl, isNotNull);

        completer.complete();
        // Bounded pumps through the pushAndRemoveUntil transition,
        // rather than pumpAndSettle: the outgoing route still paints
        // this screen's indeterminate CircularProgressIndicator for the
        // remainder of the transition, and an indeterminate animation
        // never lets pumpAndSettle observe "no more frames scheduled".
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(avatarController.avatarUrl, isNull);
      });

      testWidgets('navigates with full-stack removal: Login is shown and Back '
          'cannot return to Profile or Home', (tester) async {
        final logoutService = FakeLogoutService();
        await pumpPushedEditProfile(tester, logoutService: logoutService);

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
          await pumpPushedEditProfile(tester, logoutService: logoutService);

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
          avatarController.setAvatarUrl('http://127.0.0.1:9/avatars/7.jpg');
          await pumpPushedEditProfile(
            tester,
            logoutService: logoutService,
            avatarController: avatarController,
          );

          await tester.ensureVisible(find.byKey(logoutButton));
          await tester.tap(find.byKey(logoutButton));
          await tester.pumpAndSettle();

          expect(find.byType(EditProfileScreen), findsOneWidget);
          expect(find.byType(LoginScreen), findsNothing);
          expect(avatarController.avatarUrl, isNotNull);
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
          await pumpPushedEditProfile(tester, logoutService: logoutService);

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
        await pumpPushedEditProfile(tester, logoutService: logoutService);

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
        await pumpPushedEditProfile(tester, logoutService: logoutService);

        await tester.ensureVisible(find.byKey(logoutButton));
        await tester.tap(find.byKey(logoutButton));
        await tester.pump();

        expect(find.byType(AlertDialog), findsNothing);

        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  });

  group('Change Password entry point', () {
    testWidgets('Renders a Change Password action', (tester) async {
      await pumpEditProfile(tester);

      expect(
        find.byKey(const ValueKey('edit-profile-change-password-button')),
        findsOneWidget,
      );
      expect(find.text('Change Password'), findsOneWidget);
    });

    testWidgets('Tapping it pushes ChangePasswordScreen', (tester) async {
      await pumpPushedEditProfile(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-profile-change-password-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('edit-profile-change-password-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordScreen), findsOneWidget);
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
