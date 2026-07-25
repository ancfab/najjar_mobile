// End-to-end local-only lifecycle test: startup with no secure session ->
// login -> the secure session persists across a simulated app restart ->
// logout -> the secure session is removed -> a second simulated restart
// correctly returns to "logged out" -> the legacy Boolean cannot reopen
// Home. Exercises the real AuthService/SecureSessionService/
// SecureAuthSessionStore wiring against a recording fake http.Client
// beneath AncApiClient and an in-memory FakeSecureKeyValueStore beneath
// SecureAuthSessionStore — never a live network call, never a real
// Keychain/Keystore platform channel. A "restart" is simulated by
// constructing brand-new service instances over the same fake store, since
// production code never keeps session state in memory across launches
// either.
//
// All identifiers below (username, phone, token, bc_customer_no, password)
// are synthetic fixtures, not real or supplied backend test-account values.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anc_fabrics/config/api_config.dart';
import 'package:anc_fabrics/models/auth/login_failure.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/auth_service.dart';
import 'package:anc_fabrics/services/secure_auth_session_store.dart';
import 'package:anc_fabrics/services/session_service.dart';
import 'package:anc_fabrics/services/session_storage_keys.dart';

import '../helpers/fake_secure_key_value_store.dart';

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _respond(request as http.Request);

  @override
  void close() {}
}

http.StreamedResponse _loginSuccessResponse(http.Request request) {
  final body = jsonEncode({
    'token': 'synthetic-id|synthetic-secret',
    'must_change_password': false,
    'user': {
      'id': 7,
      'username': 'sample.user',
      'phone': '+96890000000',
      'country': 'OM',
      'client_id': ApiConfig.clientId,
      'bc_customer_no': 'SAMPLE-0001',
      'must_change_password': false,
    },
  });
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup -> login -> restart -> logout -> restart local lifecycle',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fakeSecureStore = FakeSecureKeyValueStore();

      // A fresh SecureSessionService instance over the same underlying
      // fake store, standing in for "a new app process reading the same
      // on-device secure storage" — matching how main.dart's startup gate
      // never keeps session state in memory across launches either.
      SecureSessionService freshSessionService() => SecureSessionService(
        sessionStore: SecureAuthSessionStore(secureStore: fakeSecureStore),
      );

      // 1. App starts without a secure session -> Login.
      expect(await freshSessionService().isLoggedIn(), isFalse);

      // 2. Login succeeds -> a secure AuthSession is persisted.
      final apiClient = AncApiClient(
        httpClient: _RecordingHttpClient(
          (req) async => _loginSuccessResponse(req),
        ),
      );
      final authService = AuthService(
        apiClient: apiClient,
        sessionStore: SecureAuthSessionStore(secureStore: fakeSecureStore),
      );
      final loginResult = await authService.login(
        country: 'OM',
        phone: '+96890000000',
        username: 'sample.user',
        password: 'synthetic-test-password',
      );
      expect(loginResult, isA<AuthLoginSuccess>());
      expect(await freshSessionService().isLoggedIn(), isTrue);

      // 3. Simulated app restart with the same fake secure store -> Home
      // (a brand-new SecureSessionService instance, proving persistence
      // does not depend on any in-memory state).
      expect(await freshSessionService().isLoggedIn(), isTrue);

      // 4. Logout succeeds -> the secure AuthSession is removed.
      await freshSessionService().endSession();
      expect(await freshSessionService().isLoggedIn(), isFalse);

      // 5. Simulated second restart -> Login.
      expect(await freshSessionService().isLoggedIn(), isFalse);

      // 6. The legacy Boolean cannot reopen Home even if somehow set.
      SharedPreferences.setMockInitialValues({
        SessionStorageKeys.isLoggedIn: true,
      });
      expect(await freshSessionService().isLoggedIn(), isFalse);
    },
  );
}
