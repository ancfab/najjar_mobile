// Unit tests for ApiConfig's compile-time defaults: the production ANC API
// host, the fixed distributor client id, and the relative login path that
// AncApiClient resolves requests against.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/config/api_config.dart';

void main() {
  test('baseUrl defaults to the production ANC API host', () {
    expect(ApiConfig.baseUrl, Uri.parse('https://api.ancfab.com'));
  });

  test('clientId defaults to the fixed distributor client id', () {
    expect(ApiConfig.clientId, 'ANCNAJJAR');
  });

  test('loginPath is a relative path, not an absolute URL', () {
    expect(ApiConfig.loginPath, 'api/auth/login');
    expect(ApiConfig.loginPath.startsWith('/'), isFalse);
    expect(Uri.parse(ApiConfig.loginPath).hasScheme, isFalse);
  });
}
