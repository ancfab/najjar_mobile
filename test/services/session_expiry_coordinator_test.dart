// Tests for SessionExpiryCoordinator: the centralized runtime handler for
// "an authenticated request got HTTP 401 while the user was already inside
// the app". Covers clearing the secure session, clearing in-memory
// authenticated-user/avatar state, replacing the navigation stack with
// Login, and collapsing concurrent 401s into exactly one invalidation.
//
// Uses a real SecureSessionService over a fake in-memory secure store (see
// auth_lifecycle_test.dart's convention) so "clears the secure session"
// means something concrete, not just "called a fake once".

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/models/local_customer_profile.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/services/local_customer_profile_store.dart';
import 'package:anc_fabrics/services/secure_auth_session_store.dart';
import 'package:anc_fabrics/services/session_expiry_coordinator.dart';
import 'package:anc_fabrics/services/session_service.dart';

import '../helpers/fake_secure_key_value_store.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anc_fabrics/localization/app_translations_delegate.dart';

const _syntheticToken = 'synthetic-id|synthetic-secret';

AuthSession _session() => const AuthSession(
  token: _syntheticToken,
  userId: 7,
  username: 'sample.user',
  phone: '+96890000000',
  country: 'OM',
  clientId: 'ANCNAJJAR',
  bcCustomerNo: 'SAMPLE-0001',
  mustChangePassword: false,
);

class _FakeAvatarController extends CurrentUserAvatarController {
  int clearCallCount = 0;

  @override
  void clear() {
    clearCallCount++;
    super.clear();
  }
}

class _AuthenticatedScreen extends StatelessWidget {
  const _AuthenticatedScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Authenticated Screen'));
}

void main() {
  setUp(() {
    // SecureAuthSessionStore.clear() reads/writes the legacy
    // session_is_logged_in SharedPreferences boolean; without a mock in
    // place, SharedPreferences.getInstance() never resolves in a widget
    // test (no platform to answer it), hanging these tests indefinitely
    // instead of failing fast (see account_balance_screen_test.dart's
    // identical setUp note for the avatar controller).
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'handleUnauthorized clears the secure session, clears avatar state, and '
    'replaces the stack with Login',
    (tester) async {
      final fakeSecureStore = FakeSecureKeyValueStore();
      final sessionStore = SecureAuthSessionStore(secureStore: fakeSecureStore);
      await sessionStore.save(_session());
      final avatarController = _FakeAvatarController();
      final navigatorKey = GlobalKey<NavigatorState>();
      final coordinator = SessionExpiryCoordinator(
        sessionService: SecureSessionService(sessionStore: sessionStore),
        avatarController: avatarController,
        navigatorKey: navigatorKey,
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
          navigatorKey: navigatorKey,
          home: const _AuthenticatedScreen(),
        ),
      );
      await tester.pump();
      expect(find.byType(_AuthenticatedScreen), findsOneWidget);
      expect(await sessionStore.read(), isNotNull);

      await coordinator.handleUnauthorized();
      await tester.pumpAndSettle();

      expect(
        await sessionStore.read(),
        isNull,
        reason: 'the secure session must be cleared',
      );
      expect(avatarController.clearCallCount, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.byType(_AuthenticatedScreen),
        findsNothing,
        reason: 'the authenticated screen must no longer be reachable',
      );
      // Login legitimately shows its own "session expired" message (the
      // same safe copy the cold-start startup gate uses) — what must never
      // appear is a separate endpoint-error toast on top of it.
      expect(
        find.text('Your session has expired. Please sign in again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'two simultaneous 401s collapse into exactly one invalidation and one '
    'navigation',
    (tester) async {
      final fakeSecureStore = FakeSecureKeyValueStore();
      final sessionStore = SecureAuthSessionStore(secureStore: fakeSecureStore);
      await sessionStore.save(_session());
      final avatarController = _FakeAvatarController();
      final navigatorKey = GlobalKey<NavigatorState>();
      final coordinator = SessionExpiryCoordinator(
        sessionService: SecureSessionService(sessionStore: sessionStore),
        avatarController: avatarController,
        navigatorKey: navigatorKey,
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
          navigatorKey: navigatorKey,
          home: const _AuthenticatedScreen(),
        ),
      );
      await tester.pump();

      await Future.wait([
        coordinator.handleUnauthorized(),
        coordinator.handleUnauthorized(),
      ]);
      await tester.pumpAndSettle();

      expect(avatarController.clearCallCount, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets('a third call after the guard has already fired is a no-op', (
    tester,
  ) async {
    final fakeSecureStore = FakeSecureKeyValueStore();
    final sessionStore = SecureAuthSessionStore(secureStore: fakeSecureStore);
    await sessionStore.save(_session());
    final avatarController = _FakeAvatarController();
    final navigatorKey = GlobalKey<NavigatorState>();
    final coordinator = SessionExpiryCoordinator(
      sessionService: SecureSessionService(sessionStore: sessionStore),
      avatarController: avatarController,
      navigatorKey: navigatorKey,
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
        navigatorKey: navigatorKey,
        home: const _AuthenticatedScreen(),
      ),
    );
    await tester.pump();

    await coordinator.handleUnauthorized();
    await tester.pumpAndSettle();
    await coordinator.handleUnauthorized();
    await tester.pumpAndSettle();

    expect(avatarController.clearCallCount, 1);
  });

  test('does not import local_customer_profile_store.dart — '
      'handleUnauthorized() must never clear the invalidated account\'s '
      'locally-persisted customer profile; that store is deliberately kept '
      'across session invalidation so the same account finds it restored the '
      'next time it signs in on this device', () {
    final source = File(
      'lib/services/session_expiry_coordinator.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("import 'local_customer_profile_store")));
  });

  testWidgets(
    "handleUnauthorized never touches the invalidated account's local "
    'customer profile, which remains retrievable afterward',
    (tester) async {
      final fakeSecureStore = FakeSecureKeyValueStore();
      final sessionStore = SecureAuthSessionStore(secureStore: fakeSecureStore);
      await sessionStore.save(_session());
      final localProfileStore = SecureLocalCustomerProfileStore(
        secureStore: FakeSecureKeyValueStore(),
      );
      await localProfileStore.save(
        _session().userId,
        const LocalCustomerProfile(
          fullName: 'Alexander Mitchell',
          email: 'alex.mitchell@example.com',
          company: 'Vanguard Global Logistics',
          businessAddress: '450 Fashion Ave, Suite 1205, New York, NY 10123',
        ),
      );
      final avatarController = _FakeAvatarController();
      final navigatorKey = GlobalKey<NavigatorState>();
      final coordinator = SessionExpiryCoordinator(
        sessionService: SecureSessionService(sessionStore: sessionStore),
        avatarController: avatarController,
        navigatorKey: navigatorKey,
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
          navigatorKey: navigatorKey,
          home: const _AuthenticatedScreen(),
        ),
      );
      await tester.pump();

      await coordinator.handleUnauthorized();
      await tester.pumpAndSettle();

      expect(
        await sessionStore.read(),
        isNull,
        reason: 'the secure session must still be cleared',
      );
      final restored = await localProfileStore.load(_session().userId);
      expect(restored?.fullName, 'Alexander Mitchell');
    },
  );
}
