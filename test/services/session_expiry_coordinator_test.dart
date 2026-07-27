// Tests for SessionExpiryCoordinator: the centralized runtime handler for
// "an authenticated request got HTTP 401 while the user was already inside
// the app". Covers clearing the secure session, clearing in-memory
// authenticated-user/avatar state, replacing the navigation stack with
// Login, and collapsing concurrent 401s into exactly one invalidation.
//
// Uses a real SecureSessionService over a fake in-memory secure store (see
// auth_lifecycle_test.dart's convention) so "clears the secure session"
// means something concrete, not just "called a fake once".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/screens/login_screen.dart';
import 'package:anc_fabrics/services/current_user_avatar_controller.dart';
import 'package:anc_fabrics/services/secure_auth_session_store.dart';
import 'package:anc_fabrics/services/session_expiry_coordinator.dart';
import 'package:anc_fabrics/services/session_messages.dart';
import 'package:anc_fabrics/services/session_service.dart';

import '../helpers/fake_secure_key_value_store.dart';

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
  Future<void> clear() async {
    clearCallCount++;
    await super.clear();
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
          navigatorKey: navigatorKey,
          home: const _AuthenticatedScreen(),
        ),
      );
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
      expect(find.text(sessionExpiredMessage), findsOneWidget);
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
          navigatorKey: navigatorKey,
          home: const _AuthenticatedScreen(),
        ),
      );

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
        navigatorKey: navigatorKey,
        home: const _AuthenticatedScreen(),
      ),
    );

    await coordinator.handleUnauthorized();
    await tester.pumpAndSettle();
    await coordinator.handleUnauthorized();
    await tester.pumpAndSettle();

    expect(avatarController.clearCallCount, 1);
  });
}
