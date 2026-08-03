import 'anc_api_exceptions.dart';

/// Purpose: The shared, endpoint-agnostic outcome taxonomy every Business
/// Central data-load call (ledger entries now; payments, invoices, credit
/// memos, and the rest of the six endpoints later) maps its result onto, so
/// each screen/service reacts the same controlled way rather than inventing
/// its own interpretation of a raw [AncApiException].
///
/// Responsibilities:
/// - Distinguish "the token is dead" (handled by the centralized session
///   coordinator, never shown as an endpoint error) from every other
///   failure shape a caller must render some controlled state for.
///
/// Must not:
/// - Carry a raw HTTP status code, [Exception], or the backend's raw
///   `message` as something automatically safe to show a user — see
///   [BusinessCentralFailureException.backendMessage]'s doc comment.
sealed class BusinessCentralOutcome {
  const BusinessCentralOutcome();
}

/// HTTP 401: the token is missing, invalid, or revoked. Callers must not
/// render this as an endpoint error — see `SessionExpiryCoordinator`.
class BusinessCentralUnauthorized extends BusinessCentralOutcome {
  const BusinessCentralUnauthorized();
}

/// HTTP 422 whose `errors` object names `page`/`per_page` — an app/request
/// defect, not an account-linking problem. Session and already-loaded rows
/// must be preserved.
class BusinessCentralRequestDefect extends BusinessCentralOutcome {
  const BusinessCentralRequestDefect(this.backendMessage);

  final String? backendMessage;
}

/// HTTP 422 that is not a pagination validation failure: the authenticated
/// user has no linked Business Central customer for this data.
class BusinessCentralAccountNotLinked extends BusinessCentralOutcome {
  const BusinessCentralAccountNotLinked(this.backendMessage);

  final String? backendMessage;
}

/// HTTP 503: Business Central itself is not configured/reachable
/// server-side. Not a login failure.
class BusinessCentralTemporarilyUnavailable extends BusinessCentralOutcome {
  const BusinessCentralTemporarilyUnavailable();
}

/// HTTP 502: Azure AD or Business Central failed upstream of the ANC API.
/// Transient/backend-side, not evidence of invalid credentials.
class BusinessCentralUpstreamFailure extends BusinessCentralOutcome {
  const BusinessCentralUpstreamFailure();
}

/// The request never reached the server (offline, timeout, DNS, TLS).
class BusinessCentralNetworkFailure extends BusinessCentralOutcome {
  const BusinessCentralNetworkFailure();
}

/// A malformed response body, or an HTTP status this taxonomy does not
/// otherwise recognize (any unexpected 4xx/5xx). Generic retryable failure.
class BusinessCentralProtocolFailure extends BusinessCentralOutcome {
  const BusinessCentralProtocolFailure();
}

/// Maps a transport/protocol/HTTP-level [AncApiException] from
/// [AncApiClient] onto the shared [BusinessCentralOutcome] taxonomy.
///
/// Pure and side-effect free: callers decide what to do about
/// [BusinessCentralUnauthorized] (invoke the session coordinator) — this
/// function never touches session state or navigation itself.
///
/// [supportsAccountLinking] defaults to `true`, preserving this function's
/// original behavior for the per-customer endpoints (ledger entries,
/// payments, invoices): a non-pagination 422 maps to
/// [BusinessCentralAccountNotLinked]. Pass `false` for an endpoint whose
/// data is company-scoped rather than tied to a linked Business Central
/// customer (e.g. items) — "no linked customer" cannot apply there, so
/// every 422 maps to [BusinessCentralRequestDefect] instead, matching the
/// documented contract that 422 on that endpoint only ever signals an
/// invalid `page`/`per_page` request.
BusinessCentralOutcome mapBusinessCentralError(
  AncApiException error, {
  bool supportsAccountLinking = true,
}) {
  return switch (error) {
    AncNetworkException() => const BusinessCentralNetworkFailure(),
    AncProtocolException() => const BusinessCentralProtocolFailure(),
    AncHttpException() => _mapHttpOutcome(
      error,
      supportsAccountLinking: supportsAccountLinking,
    ),
  };
}

// TODO(api): 502/503 indicate an upstream ANC API / Business Central /
// Azure AD integration failure or temporary unavailability. Flutter cannot
// determine the exact server-side cause from these status codes alone —
// preserve the authenticated session and allow retry in both cases. Only
// HTTP 401 may ever invalidate the session; 502/503 must never do so.
BusinessCentralOutcome _mapHttpOutcome(
  AncHttpException error, {
  required bool supportsAccountLinking,
}) {
  switch (error.statusCode) {
    case 401:
      return const BusinessCentralUnauthorized();
    case 422:
      final errors = error.validationError?.errors ?? const {};
      final isPaginationDefect =
          errors.containsKey('page') || errors.containsKey('per_page');
      final backendMessage = error.validationError?.message;
      if (isPaginationDefect || !supportsAccountLinking) {
        return BusinessCentralRequestDefect(backendMessage);
      }
      return BusinessCentralAccountNotLinked(backendMessage);
    case 503:
      return const BusinessCentralTemporarilyUnavailable();
    case 502:
      return const BusinessCentralUpstreamFailure();
    default:
      return const BusinessCentralProtocolFailure();
  }
}

/// Thrown by a Business Central data-load service for every
/// [BusinessCentralOutcome] except [BusinessCentralUnauthorized] — that one
/// is handled entirely by the session coordinator, never surfaced this way
/// (see [SessionExpiredException]).
class BusinessCentralFailureException implements Exception {
  const BusinessCentralFailureException(this.outcome);

  final BusinessCentralOutcome outcome;

  @override
  String toString() => 'BusinessCentralFailureException($outcome)';
}

/// Thrown after the centralized session coordinator has already cleared the
/// session and navigated to Login for an HTTP 401. Callers must catch this
/// and show nothing — no error card, no toast — since the screen is
/// expected to already be off-stack.
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'SessionExpiredException';
}
