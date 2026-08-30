// Unit tests for CustomerDetailsService: token handling via
// AuthSessionStore, the shared 401/502/503/network/malformed error mapping,
// and that dateFrom/dateTo are forwarded through to AncApiClient unchanged.
//
// All identifiers below (token) are synthetic fixtures.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/models/auth/auth_session.dart';
import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';
import 'package:anc_fabrics/services/customer_details_service.dart';

import '../helpers/fake_auth_session_store.dart';
import '../helpers/fake_session_expiry_coordinator.dart';

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

Map<String, dynamic> _validBody() => {
  'customerBalance': 36711.73,
  'availableCredit': 57150.00,
  'usedCredit': 42850.00,
};

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

class _ScriptedHttpClient extends http.BaseClient {
  _ScriptedHttpClient(this._responses);

  final List<Future<http.StreamedResponse> Function(http.Request)> _responses;
  final List<Uri> requestedUrls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requestedUrls.add(req.url);
    final handler = _responses.removeAt(0);
    return handler(req);
  }

  @override
  void close() {}
}

CustomerDetailsService _serviceWith(
  http.Client fakeHttp, {
  FakeSessionExpiryCoordinator? coordinator,
}) {
  return CustomerDetailsService(
    apiClient: AncApiClient(httpClient: fakeHttp),
    sessionStore: FakeAuthSessionStore()..seed(_session()),
    coordinator: coordinator ?? FakeSessionExpiryCoordinator(),
  );
}

void main() {
  group('CustomerDetailsService.fetchCustomerDetails', () {
    test('returns a parsed CustomerDetails on success', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(200, _validBody(), request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      final result = await service.fetchCustomerDetails();

      expect(result.customerBalance, 36711.73);
      expect(result.availableCredit, 57150.00);
      expect(result.usedCredit, 42850.00);
    });

    test('forwards dateFrom/dateTo through to the request', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(200, _validBody(), request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      await service.fetchCustomerDetails(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 30),
      );

      final url = fakeHttp.requestedUrls.single;
      expect(url.queryParameters['date_from'], '2026-01-01');
      expect(url.queryParameters['date_to'], '2026-01-30');
    });

    test('401 hands off to the coordinator exactly once and throws '
        'SessionExpiredException', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(401, const {}, request: req),
      ]);
      final coordinator = FakeSessionExpiryCoordinator();
      final service = _serviceWith(fakeHttp, coordinator: coordinator);

      await expectLater(
        service.fetchCustomerDetails(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(coordinator.handleUnauthorizedCallCount, 1);
    });

    test('HTTP 502 maps to BusinessCentralUpstreamFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(502, const {}, request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchCustomerDetails();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralUpstreamFailure>());
      }
    });

    test('HTTP 503 maps to BusinessCentralTemporarilyUnavailable', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => _jsonResponse(503, const {}, request: req),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchCustomerDetails();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralTemporarilyUnavailable>());
      }
    });

    test('a network failure maps to BusinessCentralNetworkFailure', () async {
      final fakeHttp = _ScriptedHttpClient([
        (req) async => throw const SocketException('No route to host'),
      ]);
      final service = _serviceWith(fakeHttp);

      try {
        await service.fetchCustomerDetails();
        fail('Expected a BusinessCentralFailureException');
      } on BusinessCentralFailureException catch (error) {
        expect(error.outcome, isA<BusinessCentralNetworkFailure>());
      }
    });

    test(
      'a malformed 200 body maps to BusinessCentralProtocolFailure',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => http.StreamedResponse(
            Stream.value(utf8.encode('not json')),
            200,
            request: req,
          ),
        ]);
        final service = _serviceWith(fakeHttp);

        try {
          await service.fetchCustomerDetails();
          fail('Expected a BusinessCentralFailureException');
        } on BusinessCentralFailureException catch (error) {
          expect(error.outcome, isA<BusinessCentralProtocolFailure>());
        }
      },
    );

    test(
      'an account-not-linked 422 maps to BusinessCentralAccountNotLinked',
      () async {
        final fakeHttp = _ScriptedHttpClient([
          (req) async => _jsonResponse(422, {
            'message': 'No linked Business Central customer.',
          }, request: req),
        ]);
        final service = _serviceWith(fakeHttp);

        try {
          await service.fetchCustomerDetails();
          fail('Expected a BusinessCentralFailureException');
        } on BusinessCentralFailureException catch (error) {
          expect(error.outcome, isA<BusinessCentralAccountNotLinked>());
        }
      },
    );
  });
}
