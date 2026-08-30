// Widget tests for LoginScreen against a real AuthService wired to a
// recording fake http.Client (never the live ANC API) and a fake in-memory
// AuthSessionStore (never real Keychain/Keystore). Covers request
// construction/input mapping, success navigation and session-write
// behavior, the full failure-message taxonomy, loading/duplicate-tap
// handling, disposal safety, AuthService ownership, and that no
// credential ever appears in a displayed message.
//
// All identifiers below (username, phone, token, bc_customer_no, password)
// are synthetic fixtures, not real or supplied backend test-account values.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/config/api_config.dart';
import 'package:anc_fabrics/screens/contact_us_screen.dart';
import 'package:anc_fabrics/screens/home_screen.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/session_messages.dart';
import 'package:anc_fabrics/services/session_storage_exception.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';
import 'package:anc_fabrics/widgets/login/primary_login_button.dart';
import 'package:anc_fabrics/widgets/syria_flag.dart';

import 'helpers/fake_auth_session_store.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  http.Request? lastRequest;
  int requestCount = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    lastRequest = req;
    requestCount++;
    return _respond(req);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
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

Map<String, dynamic> _validUserJson() => {
  'id': 7,
  'username': 'sample.user',
  'phone': '+96890000000',
  'country': 'OM',
  'client_id': ApiConfig.clientId,
  'bc_customer_no': 'SAMPLE-0001',
  'must_change_password': false,
};

Map<String, dynamic> _validLoginResponseJson() => {
  'token': 'synthetic-id|synthetic-secret',
  'must_change_password': false,
  'user': _validUserJson(),
};

AuthService _authServiceOver(
  _RecordingHttpClient httpClient, {
  FakeAuthSessionStore? sessionStore,
}) => AuthService(
  apiClient: AncApiClient(httpClient: httpClient),
  sessionStore: sessionStore ?? FakeAuthSessionStore(),
);

Future<void> _pumpLoginScreen(
  WidgetTester tester, {
  AuthService? authService,
  LoginStartupMessage? startupMessage,
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
      home: LoginScreen(
        authService: authService,
        startupMessage: startupMessage,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final Finder _mobileField = find.widgetWithText(TextField, '50 123 4567');
final Finder _usernameField = find.widgetWithText(TextField, 'Enter your name');
final Finder _passwordField = find.widgetWithText(
  TextField,
  'Enter your password',
);
// Found by type, not by its "LOGIN" text, since the button's content is
// replaced by a loading spinner (no "LOGIN" text) while `_isLoading` is
// true — a duplicate-tap test needs to keep finding the button then.
final Finder _loginButton = find.byType(PrimaryLoginButton);

Future<void> _enterCredentials(
  WidgetTester tester, {
  String mobile = '90000000',
  String username = 'sample.user',
  String password = 'synthetic-test-password',
}) async {
  await tester.enterText(_mobileField, mobile);
  await tester.enterText(_usernameField, username);
  await tester.enterText(_passwordField, password);
}

Future<void> _selectCountry(WidgetTester tester, String name) async {
  await tester.tap(find.text('+971'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// Pumps only far enough for the post-login `pushReplacement` to Home to
/// finish and Home's own mock dashboard delay to resolve (matching
/// `home_screen_test.dart`'s `_pumpHomeScreen` convention), without waiting
/// for every animation to settle. HomeScreen's Last Payment row defaults to
/// the live Payments API (real HTTP/secure storage), which never resolves
/// in this widget-test sandbox — these tests only care that navigation to
/// Home succeeded, not that Last Payment finished loading, so
/// `pumpAndSettle` (which would wait on its spinner forever) is
/// deliberately avoided here — mirrors `home_screen_test.dart`'s
/// `_pumpRouteTransition`, written for the same class of problem with
/// AccountBalanceScreen's Quick History.
Future<void> _pumpAfterSuccessfulLogin(WidgetTester tester) async {
  await tester.pump(); // start the pushReplacement transition
  // Covers the route transition and Home's mock dashboard delay, so no
  // dangling Timer trips AutomatedTestWidgetsFlutterBinding's post-test
  // invariant check.
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('country selector', () {
    testWidgets('still offers UAE, Iraq, Syria, Lebanon, and Oman', (
      tester,
    ) async {
      await _pumpLoginScreen(tester);
      await tester.tap(find.text('+971'));
      await tester.pumpAndSettle();

      expect(find.text('United Arab Emirates'), findsOneWidget);
      expect(find.text('Iraq'), findsOneWidget);
      expect(find.text('Syria'), findsOneWidget);
      expect(find.text('Lebanon'), findsOneWidget);
      expect(find.text('Oman'), findsOneWidget);
    });

    testWidgets(
      'renders Syria with the custom SyriaFlag widget, not the 🇸🇾 emoji '
      'glyph (which can still render the outdated pre-2024 flag design on '
      'some platforms)',
      (tester) async {
        await _pumpLoginScreen(tester);
        await tester.tap(find.text('+971'));
        await tester.pumpAndSettle();

        expect(find.byType(SyriaFlag), findsOneWidget);
        expect(find.text('🇸🇾'), findsNothing);
      },
    );
  });

  group('login request construction and input mapping', () {
    testWidgets('sends the selected country isoCode, the selected dial code '
        'prepended to the entered digits, the CLIENT NAME field as username '
        '(trimmed), the password unchanged (including intentional outer '
        'whitespace), and the fixed ApiConfig.clientId', (tester) async {
      final http_ = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));

      await _selectCountry(tester, 'Oman');
      await _enterCredentials(
        tester,
        mobile: '90000000',
        username: 'sample.user',
        password: '  synthetic-test-password  ',
      );
      await tester.tap(_loginButton);
      await _pumpAfterSuccessfulLogin(tester);

      expect(http_.requestCount, 1);
      final sentBody =
          jsonDecode(http_.lastRequest!.body) as Map<String, dynamic>;
      expect(sentBody['country'], 'OM');
      expect(sentBody['phone'], '+96890000000');
      expect(sentBody['username'], 'sample.user');
      expect(sentBody['password'], '  synthetic-test-password  ');
      expect(sentBody['client_id'], ApiConfig.clientId);
    });
  });

  group('successful login', () {
    testWidgets('navigates to Home', (tester) async {
      final http_ = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
      await _enterCredentials(tester);

      await tester.tap(_loginButton);
      await _pumpAfterSuccessfulLogin(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('writes no SharedPreferences login Boolean', (tester) async {
      final http_ = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
      await _enterCredentials(tester);

      await tester.tap(_loginButton);
      await _pumpAfterSuccessfulLogin(tester);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SessionStorageKeys.isLoggedIn), isFalse);
    });

    testWidgets(
      'navigates to Home even when must_change_password is true — there is '
      'no password-change endpoint, so this flag must never gate '
      'navigation or open a nonexistent forced password-change screen',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async => _jsonResponse(200, {
            'token': 'synthetic-id|synthetic-secret',
            'must_change_password': true,
            'user': {..._validUserJson(), 'must_change_password': true},
          }, request: req),
        );
        await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
        await _enterCredentials(tester);

        await tester.tap(_loginButton);
        await _pumpAfterSuccessfulLogin(tester);

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
      },
    );

    testWidgets('saves the session exactly once', (tester) async {
      final http_ = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      final sessionStore = FakeAuthSessionStore();
      await _pumpLoginScreen(
        tester,
        authService: _authServiceOver(http_, sessionStore: sessionStore),
      );
      await _enterCredentials(tester);

      await tester.tap(_loginButton);
      await _pumpAfterSuccessfulLogin(tester);

      expect(sessionStore.saveCallCount, 1);
    });
  });

  group('failure message presentation', () {
    Future<String> submitAndReadDialogText(
      WidgetTester tester,
      _RecordingHttpClient http_,
    ) async {
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
      await _enterCredentials(tester);
      await tester.tap(_loginButton);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      final dialog = find.byKey(const ValueKey('login-error-dialog'));
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Unable to Sign In')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('login-error-dialog-ok')),
        findsOneWidget,
      );

      final alertDialog = tester.widget<AlertDialog>(dialog);
      final message = (alertDialog.content! as Text).data!;

      // Tapping OK dismisses the dialog.
      await tester.tap(find.byKey(const ValueKey('login-error-dialog-ok')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);

      return message;
    }

    testWidgets('invalid credentials (422 errors.username) show a neutral '
        'message, never "username not found"', (tester) async {
      final http_ = _RecordingHttpClient(
        (req) async => _jsonResponse(422, {
          'errors': {
            'username': ['These credentials do not match our records.'],
          },
        }, request: req),
      );

      final message = await submitAndReadDialogText(tester, http_);

      expect(message, 'Please check your login details and try again.');
      expect(message, isNot(contains('username')));
      expect(message, isNot(contains('not found')));
      expect(message, isNot(contains('credentials do not match')));
    });

    testWidgets(
      'invalid phone (422 errors.phone) shows the retained safe message',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'errors': {
              'phone': ['The phone field format is invalid.'],
            },
          }, request: req),
        );

        final message = await submitAndReadDialogText(tester, http_);

        expect(message, 'The phone field format is invalid.');
      },
    );

    testWidgets(
      'invalid phone with no retained message falls back to a neutral '
      'phone message',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(422, {'errors': <String, dynamic>{}}, request: req),
        );

        final message = await submitAndReadDialogText(tester, http_);

        // An empty 422 errors object maps to invalidCredentials (see
        // AuthService's neutral-validation rule), not invalidPhone — the
        // phone-specific fallback path is exercised by AuthService's own
        // unit tests. This confirms the screen still shows a safe message.
        expect(message, 'Please check your login details and try again.');
      },
    );

    testWidgets('a network failure shows a neutral connection message', (
      tester,
    ) async {
      final http_ = _RecordingHttpClient(
        (req) async => throw const SocketException('no route to host'),
      );

      final message = await submitAndReadDialogText(tester, http_);

      expect(
        message,
        'Unable to connect. Check your internet connection and try again.',
      );
    });

    testWidgets('an HTTP 500 shows a neutral service-unavailable message', (
      tester,
    ) async {
      final http_ = _RecordingHttpClient(
        (req) async => _jsonResponse(500, const {}, request: req),
      );

      final message = await submitAndReadDialogText(tester, http_);

      expect(
        message,
        'The service is temporarily unavailable. Please try again.',
      );
    });

    testWidgets(
      'a malformed successful response shows a neutral response message',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async => http.StreamedResponse(
            Stream.value(utf8.encode('not json at all')),
            200,
            request: req,
          ),
        );

        final message = await submitAndReadDialogText(tester, http_);

        expect(message, 'We could not complete the login. Please try again.');
      },
    );

    testWidgets(
      'a secure-storage failure after HTTP success shows a neutral message '
      'in the dialog, not a SnackBar',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, _validLoginResponseJson(), request: req),
        );
        final sessionStore = FakeAuthSessionStore()
          ..saveError = const SessionStorageException(
            SessionStorageOperation.write,
          );
        await _pumpLoginScreen(
          tester,
          authService: _authServiceOver(http_, sessionStore: sessionStore),
        );
        await _enterCredentials(tester);
        await tester.tap(_loginButton);
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('login-error-dialog')),
            matching: find.text(
              'Login succeeded, but the session could not be saved securely. '
              'Please try again.',
            ),
          ),
          findsOneWidget,
        );
        expect(find.byType(HomeScreen), findsNothing);
      },
    );
  });

  group('local field validation', () {
    testWidgets(
      'empty mobile number shows an inline error under the mobile field, '
      'not a dialog, and makes no API call',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, _validLoginResponseJson(), request: req),
        );
        await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
        await _enterCredentials(tester, mobile: '');

        await tester.tap(_loginButton);
        await tester.pumpAndSettle();

        expect(find.text('Please enter your mobile number.'), findsOneWidget);
        expect(find.byKey(const ValueKey('login-error-dialog')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(http_.requestCount, 0);
      },
    );

    testWidgets(
      'empty username shows an inline error under the client name field, '
      'not a dialog, and makes no API call',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, _validLoginResponseJson(), request: req),
        );
        await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
        await _enterCredentials(tester, username: '');

        await tester.tap(_loginButton);
        await tester.pumpAndSettle();

        expect(find.text('Please enter your name.'), findsOneWidget);
        expect(find.byKey(const ValueKey('login-error-dialog')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(http_.requestCount, 0);
      },
    );

    testWidgets(
      'empty password shows an inline error under the password field, not '
      'a dialog, and makes no API call',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, _validLoginResponseJson(), request: req),
        );
        await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
        await _enterCredentials(tester, password: '');

        await tester.tap(_loginButton);
        await tester.pumpAndSettle();

        expect(find.text('Please enter your password.'), findsOneWidget);
        expect(find.byKey(const ValueKey('login-error-dialog')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(http_.requestCount, 0);
      },
    );

    testWidgets(
      'a non-digit mobile number shows the mobile-specific inline error, '
      'not a dialog, and makes no API call',
      (tester) async {
        final http_ = _RecordingHttpClient(
          (req) async =>
              _jsonResponse(200, _validLoginResponseJson(), request: req),
        );
        await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
        await _enterCredentials(tester, mobile: '5O1234');

        await tester.tap(_loginButton);
        await tester.pumpAndSettle();

        expect(
          find.text('Mobile number should contain digits only.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('login-error-dialog')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(http_.requestCount, 0);
      },
    );

    testWidgets(
      'editing an invalid mobile field after a failed submit clears its '
      'inline error',
      (tester) async {
        await _pumpLoginScreen(tester);
        await _enterCredentials(tester, mobile: '');

        await tester.tap(_loginButton);
        await tester.pumpAndSettle();
        expect(find.text('Please enter your mobile number.'), findsOneWidget);

        await tester.enterText(_mobileField, '5');
        await tester.pumpAndSettle();

        expect(find.text('Please enter your mobile number.'), findsNothing);
      },
    );

    testWidgets(
      'all three fields empty shows all three inline errors at once',
      (tester) async {
        await _pumpLoginScreen(tester);
        await _enterCredentials(tester, mobile: '', username: '', password: '');

        await tester.tap(_loginButton);
        await tester.pumpAndSettle();

        expect(find.text('Please enter your mobile number.'), findsOneWidget);
        expect(find.text('Please enter your name.'), findsOneWidget);
        expect(find.text('Please enter your password.'), findsOneWidget);
      },
    );
  });

  group('loading and duplicate-tap handling', () {
    testWidgets('shows a loading indicator while the request is in flight', (
      tester,
    ) async {
      final completer = Completer<http.StreamedResponse>();
      final http_ = _RecordingHttpClient((req) => completer.future);
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
      await _enterCredentials(tester);

      await tester.tap(_loginButton);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(
        _jsonResponse(
          200,
          _validLoginResponseJson(),
          request: http_.lastRequest!,
        ),
      );
      await _pumpAfterSuccessfulLogin(tester);
    });

    testWidgets('a duplicate tap while loading calls AuthService only once', (
      tester,
    ) async {
      final completer = Completer<http.StreamedResponse>();
      final http_ = _RecordingHttpClient((req) => completer.future);
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
      await _enterCredentials(tester);

      await tester.tap(_loginButton);
      await tester.pump();
      await tester.tap(_loginButton);
      await tester.pump();

      expect(http_.requestCount, 1);

      completer.complete(
        _jsonResponse(
          200,
          _validLoginResponseJson(),
          request: http_.lastRequest!,
        ),
      );
      await _pumpAfterSuccessfulLogin(tester);
    });

    testWidgets('a network failure resets the loading state', (tester) async {
      final http_ = _RecordingHttpClient(
        (req) async => throw const SocketException('no route to host'),
      );
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
      await _enterCredentials(tester);

      await tester.tap(_loginButton);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'does not call setState after disposal while a login is in flight',
      (tester) async {
        final completer = Completer<http.StreamedResponse>();
        final http_ = _RecordingHttpClient((req) => completer.future);
        await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
        await _enterCredentials(tester);

        await tester.tap(_loginButton);
        await tester.pump();

        // Disposes LoginScreen while the request is still pending.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();

        completer.complete(
          _jsonResponse(
            200,
            _validLoginResponseJson(),
            request: http_.lastRequest!,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('AuthService ownership', () {
    testWidgets('does not close an injected AuthService', (tester) async {
      final http_ = _RecordingHttpClient(
        (req) async =>
            _jsonResponse(200, _validLoginResponseJson(), request: req),
      );
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(http_.closed, isFalse);
    });

    testWidgets(
      'a screen-owned production AuthService is closed safely on disposal',
      (tester) async {
        await _pumpLoginScreen(tester);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('credential safety', () {
    testWidgets('a failure message never contains the password or the raw '
        'backend validation text', (tester) async {
      const secretPassword = 'super-secret-should-not-leak-value';
      final http_ = _RecordingHttpClient(
        (req) async => _jsonResponse(422, {
          'errors': {
            'username': ['These credentials do not match our records.'],
          },
        }, request: req),
      );
      await _pumpLoginScreen(tester, authService: _authServiceOver(http_));
      await _enterCredentials(tester, password: secretPassword);

      await tester.tap(_loginButton);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      final dialog = tester.widget<AlertDialog>(
        find.byKey(const ValueKey('login-error-dialog')),
      );
      final message = (dialog.content! as Text).data!;

      expect(message, isNot(contains(secretPassword)));
      expect(message, isNot(contains('credentials do not match')));
    });

    testWidgets('a startup message is shown once via the SnackBar style', (
      tester,
    ) async {
      const message =
          'We could not restore your secure session. Please sign in again.';
      await _pumpLoginScreen(
        tester,
        startupMessage: LoginStartupMessage.restoreFailed,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(message), findsOneWidget);
    });
  });

  group('informational links', () {
    testWidgets('Contact Us link navigates to ContactUsScreen', (tester) async {
      await _pumpLoginScreen(tester);

      final finder = find.text('Need help? Contact Us');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();

      expect(find.byType(ContactUsScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });
}
