// Unit tests for mapBusinessCentralError: the shared outcome taxonomy every
// Business Central endpoint (ledger entries now, five more later) maps its
// AncApiException onto.

import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/models/auth/api_validation_error.dart';
import 'package:anc_fabrics/services/anc_api_exceptions.dart';
import 'package:anc_fabrics/services/business_central_error_mapper.dart';

void main() {
  group('mapBusinessCentralError', () {
    test('401 maps to BusinessCentralUnauthorized', () {
      final outcome = mapBusinessCentralError(
        const AncHttpException('unauthorized', statusCode: 401),
      );
      expect(outcome, isA<BusinessCentralUnauthorized>());
    });

    test('422 with errors.page maps to BusinessCentralRequestDefect', () {
      final outcome = mapBusinessCentralError(
        AncHttpException(
          'bad request',
          statusCode: 422,
          validationError: ApiValidationError.fromJson({
            'message': 'The given data was invalid.',
            'errors': {
              'page': ['The page field is invalid.'],
            },
          }),
        ),
      );
      expect(outcome, isA<BusinessCentralRequestDefect>());
    });

    test('422 with errors.per_page maps to BusinessCentralRequestDefect', () {
      final outcome = mapBusinessCentralError(
        AncHttpException(
          'bad request',
          statusCode: 422,
          validationError: ApiValidationError.fromJson({
            'errors': {
              'per_page': ['The per_page field is invalid.'],
            },
          }),
        ),
      );
      expect(outcome, isA<BusinessCentralRequestDefect>());
    });

    test(
      '422 without a page/per_page error maps to BusinessCentralAccountNotLinked',
      () {
        final outcome = mapBusinessCentralError(
          AncHttpException(
            'not linked',
            statusCode: 422,
            validationError: ApiValidationError.fromJson({
              'message': 'No linked Business Central customer.',
            }),
          ),
        );
        expect(outcome, isA<BusinessCentralAccountNotLinked>());
        expect(
          (outcome as BusinessCentralAccountNotLinked).backendMessage,
          'No linked Business Central customer.',
        );
      },
    );

    test(
      '422 with no validation body maps to BusinessCentralAccountNotLinked',
      () {
        final outcome = mapBusinessCentralError(
          const AncHttpException('unlinked', statusCode: 422),
        );
        expect(outcome, isA<BusinessCentralAccountNotLinked>());
      },
    );

    test('503 maps to BusinessCentralTemporarilyUnavailable', () {
      final outcome = mapBusinessCentralError(
        const AncHttpException('unavailable', statusCode: 503),
      );
      expect(outcome, isA<BusinessCentralTemporarilyUnavailable>());
    });

    test('502 maps to BusinessCentralUpstreamFailure', () {
      final outcome = mapBusinessCentralError(
        const AncHttpException('bad gateway', statusCode: 502),
      );
      expect(outcome, isA<BusinessCentralUpstreamFailure>());
    });

    test('an unexpected 500 maps to BusinessCentralProtocolFailure', () {
      final outcome = mapBusinessCentralError(
        const AncHttpException('server error', statusCode: 500),
      );
      expect(outcome, isA<BusinessCentralProtocolFailure>());
    });

    test('a network exception maps to BusinessCentralNetworkFailure', () {
      final outcome = mapBusinessCentralError(
        const AncNetworkException('offline'),
      );
      expect(outcome, isA<BusinessCentralNetworkFailure>());
    });

    test('a protocol exception maps to BusinessCentralProtocolFailure', () {
      final outcome = mapBusinessCentralError(
        const AncProtocolException('malformed body'),
      );
      expect(outcome, isA<BusinessCentralProtocolFailure>());
    });
  });
}
