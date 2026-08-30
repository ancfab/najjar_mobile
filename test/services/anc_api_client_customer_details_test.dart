// Unit tests for AncApiClient.fetchCustomerDetails against a recording fake
// http.Client — never the live ANC API. Covers request construction (URL,
// no date filters vs. date_from/date_to, headers, absence of a customer
// identifier), response decoding (200, 422, malformed body, other non-2xx),
// and that no pagination parameters are ever sent (this endpoint is not
// paginated).
//
// The token below is a synthetic fixture, not a real or supplied backend
// test-account value.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anc_fabrics/services/anc_api_client.dart';
import 'package:anc_fabrics/services/anc_api_exceptions.dart';

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  http.Request? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    lastRequest = req;
    return _respond(req);
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

Map<String, dynamic> _validBody() => {
  'customerBalance': 36711.73,
  'availableCredit': 57150.00,
  'usedCredit': 42850.00,
};

void main() {
  const syntheticToken = 'synthetic-id|synthetic-secret';

  group('AncApiClient.fetchCustomerDetails', () {
    test(
      'GETs the customer-details path with no query when no dates are given',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, _validBody(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchCustomerDetails(token: syntheticToken);

        expect(fake.lastRequest!.method, 'GET');
        expect(
          fake.lastRequest!.url,
          Uri.parse(
            'https://api.ancfab.com/api/business-central/customer-details',
          ),
        );
      },
    );

    test('sends date_from/date_to as yyyy-MM-dd when both are given', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, _validBody(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchCustomerDetails(
        token: syntheticToken,
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 30),
      );

      expect(fake.lastRequest!.url.queryParameters['date_from'], '2026-01-01');
      expect(fake.lastRequest!.url.queryParameters['date_to'], '2026-01-30');
    });

    test('omits date_from entirely when only date_to is given', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, _validBody(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchCustomerDetails(
        token: syntheticToken,
        dateTo: DateTime(2026, 1, 30),
      );

      expect(
        fake.lastRequest!.url.queryParameters.containsKey('date_from'),
        isFalse,
      );
      expect(fake.lastRequest!.url.queryParameters['date_to'], '2026-01-30');
    });

    test(
      'sends Accept: application/json and Authorization: Bearer <token>',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, _validBody(), request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await client.fetchCustomerDetails(token: syntheticToken);

        expect(fake.lastRequest!.headers['Accept'], 'application/json');
        expect(
          fake.lastRequest!.headers['Authorization'],
          'Bearer $syntheticToken',
        );
      },
    );

    test('never sends a customer_no/page/per_page query parameter', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, _validBody(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await client.fetchCustomerDetails(
        token: syntheticToken,
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 30),
      );

      final params = fake.lastRequest!.url.queryParameters;
      expect(params.containsKey('customer_no'), isFalse);
      expect(params.containsKey('page'), isFalse);
      expect(params.containsKey('per_page'), isFalse);
    });

    test('parses a 200 body into CustomerDetails', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(200, _validBody(), request: req),
      );
      final client = AncApiClient(httpClient: fake);

      final result = await client.fetchCustomerDetails(token: syntheticToken);

      expect(result.customerBalance, 36711.73);
      expect(result.availableCredit, 57150.00);
      expect(result.usedCredit, 42850.00);
    });

    test('HTTP 401 raises AncHttpException with statusCode 401', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(401, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchCustomerDetails(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 401);
      }
    });

    test(
      'an account-not-linked 422 exposes its message via validationError',
      () async {
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(422, {
            'message': 'No linked Business Central customer.',
          }, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        try {
          await client.fetchCustomerDetails(token: syntheticToken);
          fail('Expected an AncHttpException');
        } on AncHttpException catch (error) {
          expect(error.statusCode, 422);
          expect(
            error.validationError?.message,
            'No linked Business Central customer.',
          );
        }
      },
    );

    test('HTTP 502 raises AncHttpException with statusCode 502', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(502, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchCustomerDetails(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 502);
      }
    });

    test('HTTP 503 raises AncHttpException with statusCode 503', () async {
      final fake = _RecordingHttpClient(
        (req) async => _jsonResponse(503, const {}, request: req),
      );
      final client = AncApiClient(httpClient: fake);

      try {
        await client.fetchCustomerDetails(token: syntheticToken);
        fail('Expected an AncHttpException');
      } on AncHttpException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('a network failure raises AncNetworkException', () async {
      final fake = _RecordingHttpClient(
        (req) async => throw const SocketException('No route to host'),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchCustomerDetails(token: syntheticToken),
        throwsA(isA<AncNetworkException>()),
      );
    });

    test('a malformed 200 body raises AncProtocolException', () async {
      final fake = _RecordingHttpClient(
        (req) async => _rawResponse(200, 'not json at all', request: req),
      );
      final client = AncApiClient(httpClient: fake);

      await expectLater(
        client.fetchCustomerDetails(token: syntheticToken),
        throwsA(isA<AncProtocolException>()),
      );
    });

    test(
      'a 200 body missing customerBalance raises AncProtocolException',
      () async {
        final body = _validBody()..remove('customerBalance');
        final fake = _RecordingHttpClient(
          (req) async => _jsonResponse(200, body, request: req),
        );
        final client = AncApiClient(httpClient: fake);

        await expectLater(
          client.fetchCustomerDetails(token: syntheticToken),
          throwsA(isA<AncProtocolException>()),
        );
      },
    );
  });
}
