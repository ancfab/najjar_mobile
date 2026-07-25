import '../models/auth/api_validation_error.dart';

/// Purpose: Typed failures [AncApiClient] raises, so callers never need to
/// catch raw `dart:io`/`http`/JSON exceptions or inspect a raw response
/// body themselves.
///
/// Responsibilities:
/// - Distinguish transport failures (no response reached) from protocol
///   failures (a response was reached but its body was not the expected
///   shape) from HTTP-level failures (a well-formed non-2xx response).
///
/// Must not:
/// - Carry a [message] intended for direct end-user display — the future
///   AuthService/LoginScreen decide user-facing wording.
sealed class AncApiException implements Exception {
  const AncApiException(this.message);

  /// Short, developer-facing description. Not user-facing copy.
  final String message;

  @override
  String toString() => 'AncApiException: $message';
}

/// The request never reached the server, or no response was received (e.g.
/// offline, DNS failure, connection reset).
class AncNetworkException extends AncApiException {
  const AncNetworkException(super.message);
}

/// A response was received but its body did not match the shape the caller
/// expected (non-JSON body, or well-formed JSON missing required fields).
class AncProtocolException extends AncApiException {
  const AncProtocolException(super.message);
}

/// A well-formed HTTP response was received with a non-2xx status code.
/// [statusCode] and, for HTTP 422, [validationError] let callers decide how
/// to react without re-parsing the response themselves.
class AncHttpException extends AncApiException {
  const AncHttpException(
    super.message, {
    required this.statusCode,
    this.validationError,
  });

  final int statusCode;

  /// Parsed 422 validation error body, when [statusCode] is 422. Null for
  /// every other status.
  final ApiValidationError? validationError;
}
