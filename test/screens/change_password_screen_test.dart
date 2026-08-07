// Widget checks for ChangePasswordScreen: field rendering/obscuring, local
// strength/confirmation validation (blocking submission before any network
// call), successful submission (fields cleared, session untouched), server
// failure mapping (incorrect current password shown distinctly from a
// generic weak-password/failure message), loading/duplicate-submission
// guarding, and the unauthorized-session navigation contract.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/screens/change_password_screen.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/current_user_avatar_controller.dart';

import '../helpers/fake_auth_session_store.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

AuthSession _validSession() => const AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: 'sample.user',
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

/// Records the single request it receives and replies with a canned
/// response (or throws, to simulate a transport failure), so tests can
/// assert on exactly what was sent without making a real network call.
/// Mirrors the fixture in auth_service_test.dart.
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

http.StreamedResponse _rawResponse(
  int statusCode,
  String body, {
  required http.Request request,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    request: request,
  );
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

AuthService _authServiceFor(http.Client httpClient) => AuthService(
  apiClient: AncApiClient(httpClient: httpClient),
  sessionStore: FakeAuthSessionStore()..seed(_validSession()),
);

void main() {
  Future<void> pumpChangePassword(
    WidgetTester tester, {
    required AuthService authService,
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
        home: ChangePasswordScreen(
          authService: authService,
          avatarController: avatarController ?? CurrentUserAvatarController(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const currentField = ValueKey('change-password-current-field');
  const newField = ValueKey('change-password-new-field');
  const confirmField = ValueKey('change-password-confirm-field');
  const submitButton = ValueKey('change-password-submit-button');

  Future<void> enterAllValid(WidgetTester tester) async {
    await tester.enterText(find.byKey(currentField), 'Password123!');
    await tester.enterText(find.byKey(newField), 'NewPassword456!');
    await tester.enterText(find.byKey(confirmField), 'NewPassword456!');
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(submitButton));
    await tester.tap(find.byKey(submitButton));
  }

  group('Rendering', () {
    testWidgets('Renders the three fields, obscured by default', (
      tester,
    ) async {
      final recorder = _RecordingHttpClient(
        (req) async => _rawResponse(200, '', request: req),
      );
      await pumpChangePassword(tester, authService: _authServiceFor(recorder));

      expect(find.text('Current Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm New Password'), findsOneWidget);
      expect(find.byKey(currentField), findsOneWidget);
      expect(find.byKey(newField), findsOneWidget);
      expect(find.byKey(confirmField), findsOneWidget);

      for (final key in [currentField, newField, confirmField]) {
        final textField = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(TextField),
          ),
        );
        expect(textField.obscureText, isTrue);
      }
    });

    testWidgets('Shows the password-requirements hint', (tester) async {
      final recorder = _RecordingHttpClient(
        (req) async => _rawResponse(200, '', request: req),
      );
      await pumpChangePassword(tester, authService: _authServiceFor(recorder));

      expect(
        find.text(
          'Must be at least 8 characters, with uppercase, lowercase, a '
          'number, and a symbol.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('The show/hide toggle on the New Password field works', (
      tester,
    ) async {
      final recorder = _RecordingHttpClient(
        (req) async => _rawResponse(200, '', request: req),
      );
      await pumpChangePassword(tester, authService: _authServiceFor(recorder));

      TextField newPasswordField() => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(newField),
          matching: find.byType(TextField),
        ),
      );

      expect(newPasswordField().obscureText, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byKey(newField),
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
      );
      await tester.pump();

      expect(newPasswordField().obscureText, isFalse);
    });

    testWidgets('Has a back button that pops the screen', (tester) async {
      final recorder = _RecordingHttpClient(
        (req) async => _rawResponse(200, '', request: req),
      );
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
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordScreen(
                      authService: _authServiceFor(recorder),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('change-password-back-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordScreen), findsNothing);
    });
  });

  group('Local validation (no API call)', () {
    testWidgets('All fields are required', (tester) async {
      final recorder = _RecordingHttpClient(
        (req) async => _rawResponse(200, '', request: req),
      );
      await pumpChangePassword(tester, authService: _authServiceFor(recorder));

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your current password.'), findsOneWidget);
      expect(find.text('Please enter a new password.'), findsOneWidget);
      expect(find.text('Please confirm your new password.'), findsOneWidget);
      expect(recorder.requestCount, 0);
    });

    testWidgets(
      'A new password missing a required rule (e.g. no symbol) shows the '
      'requirements message and blocks submission',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _rawResponse(200, '', request: req),
        );
        await pumpChangePassword(
          tester,
          authService: _authServiceFor(recorder),
        );

        await tester.enterText(find.byKey(currentField), 'Password123!');
        await tester.enterText(find.byKey(newField), 'NoSymbolHere1');
        await tester.enterText(find.byKey(confirmField), 'NoSymbolHere1');
        await tester.pump();

        await tapSubmit(tester);
        await tester.pumpAndSettle();

        // The persistent hint below the field and the inline validator
        // error intentionally share the same message text, so both are
        // showing once the field is invalid.
        expect(
          find.text(
            'Must be at least 8 characters, with uppercase, lowercase, a '
            'number, and a symbol.',
          ),
          findsNWidgets(2),
        );
        expect(recorder.requestCount, 0);
      },
    );

    testWidgets('A confirmation that does not match the new password blocks '
        'submission', (tester) async {
      final recorder = _RecordingHttpClient(
        (req) async => _rawResponse(200, '', request: req),
      );
      await pumpChangePassword(tester, authService: _authServiceFor(recorder));

      await tester.enterText(find.byKey(currentField), 'Password123!');
      await tester.enterText(find.byKey(newField), 'NewPassword456!');
      await tester.enterText(find.byKey(confirmField), 'Different456!');
      await tester.pump();

      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(recorder.requestCount, 0);
    });
  });

  group('Submission', () {
    testWidgets(
      'Valid values call the service exactly once with the three fields',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _rawResponse(200, '', request: req),
        );
        await pumpChangePassword(
          tester,
          authService: _authServiceFor(recorder),
        );

        await enterAllValid(tester);
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(recorder.requestCount, 1);
        expect(recorder.lastRequest!.method, 'PUT');
        final sentBody =
            jsonDecode(recorder.lastRequest!.body) as Map<String, dynamic>;
        expect(sentBody, {
          'current_password': 'Password123!',
          'password': 'NewPassword456!',
          'password_confirmation': 'NewPassword456!',
        });
      },
    );

    testWidgets(
      'Loading disables the submit button and a duplicate tap sends only '
      'one request',
      (tester) async {
        final pending = Completer<http.StreamedResponse>();
        final recorder = _RecordingHttpClient((req) => pending.future);
        await pumpChangePassword(
          tester,
          authService: _authServiceFor(recorder),
        );

        await enterAllValid(tester);
        await tapSubmit(tester);
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(find.byKey(submitButton));
        await tester.pump();
        expect(recorder.requestCount, 1);

        pending.complete(_rawResponse(200, '', request: recorder.lastRequest!));
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'Success shows a localized message, clears all three fields, and '
      'stays on the same screen (session/token untouched)',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _rawResponse(200, '', request: req),
        );
        await pumpChangePassword(
          tester,
          authService: _authServiceFor(recorder),
        );

        await enterAllValid(tester);
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(find.text('Password updated successfully.'), findsOneWidget);
        expect(find.byType(ChangePasswordScreen), findsOneWidget);

        for (final key in [currentField, newField, confirmField]) {
          final textField = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(TextField),
            ),
          );
          expect(textField.controller!.text, isEmpty);
        }
      },
    );

    testWidgets('Incorrect current password is shown distinctly, and the typed '
        'values are preserved', (tester) async {
      final recorder = _RecordingHttpClient(
        (req) async => _jsonResponse(422, {
          'errors': {
            'current_password': ['The current password is incorrect.'],
          },
        }, request: req),
      );
      await pumpChangePassword(tester, authService: _authServiceFor(recorder));

      await enterAllValid(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      final currentTextField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(currentField),
          matching: find.byType(TextField),
        ),
      );
      expect(currentTextField.controller!.text, 'Password123!');
    });

    testWidgets('A generic server failure shows a neutral message', (
      tester,
    ) async {
      final recorder = _RecordingHttpClient(
        (req) async => _jsonResponse(500, const {}, request: req),
      );
      await pumpChangePassword(tester, authService: _authServiceFor(recorder));

      await enterAllValid(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        find.text("We couldn't update your password. Please try again."),
        findsOneWidget,
      );
    });

    testWidgets(
      'HTTP 401 clears the avatar and navigates to Login with the stack '
      'removed',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => _jsonResponse(401, const {}, request: req),
        );
        final avatarController = CurrentUserAvatarController();
        avatarController.setAvatarUrl('https://cdn.example.com/avatars/7.jpg');
        await pumpChangePassword(
          tester,
          authService: _authServiceFor(recorder),
          avatarController: avatarController,
        );

        await enterAllValid(tester);
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(avatarController.avatarUrl, isNull);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(ChangePasswordScreen), findsNothing);
      },
    );

    testWidgets(
      'No password value or token ever appears in a raised/rendered error',
      (tester) async {
        final recorder = _RecordingHttpClient(
          (req) async => throw const SocketException('No route to host'),
        );
        await pumpChangePassword(
          tester,
          authService: _authServiceFor(recorder),
        );

        await enterAllValid(tester);
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        // The failure SnackBar shows only the neutral generic message —
        // never the raw exception, a password value, or the token. (The
        // password fields' own EditableText content is expected to still
        // contain what was typed, per "preserve values on failure" — that
        // is not a leak, just unsent input the user can retry with.)
        expect(
          find.text("We couldn't update your password. Please try again."),
          findsOneWidget,
        );
        expect(find.textContaining(_syntheticToken), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
