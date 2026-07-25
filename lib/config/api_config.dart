/// Purpose: Centralizes the ANC API's network configuration for this
/// distributor build.
///
/// Responsibilities:
/// - Provide the ANC API base URL as a parsed [Uri] so no other file has to
///   hardcode or reconstruct the host.
/// - Provide the fixed distributor `client_id` every login request sends.
/// - Provide the relative login endpoint path.
///
/// Must not:
/// - Contain any Business Central URL, credential, or connection detail —
///   the Flutter app talks only to the ANC API, which owns the Business
///   Central connection on the authenticated user's behalf.
/// - Expose [clientId] as a user-visible or editable form field; it is
///   fixed build configuration, not user input.
class ApiConfig {
  ApiConfig._();

  /// The ANC API host. Overridable at build/test time via
  /// `--dart-define=ANC_API_BASE_URL=...`; defaults to production.
  static const String _baseUrlString = String.fromEnvironment(
    'ANC_API_BASE_URL',
    defaultValue: 'https://api.ancfab.com',
  );

  /// Parsed ANC API base URL. Every request URL is built from this by
  /// [AncApiClient] — no other file should hardcode or reconstruct the
  /// host.
  static final Uri baseUrl = Uri.parse(_baseUrlString);

  /// Fixed distributor client identifier for this build. Not a secret: it
  /// identifies the distributor app instance to the ANC API, not a user,
  /// and is supplied by [AuthService] — never a LoginScreen form field.
  static const String clientId = String.fromEnvironment(
    'ANC_API_CLIENT_ID',
    defaultValue: 'ANCNAJJAR',
  );

  /// Relative path (no leading slash) for the login endpoint, resolved
  /// against [baseUrl] by [AncApiClient].
  static const String loginPath = 'api/auth/login';

  /// Default per-request timeout applied by [AncApiClient]. A timeout is a
  /// transport failure (mapped to [AncNetworkException]), not a session
  /// event — it must never clear an authenticated session, only the ANC
  /// API's HTTP 401 does that.
  static const Duration requestTimeout = Duration(seconds: 15);
}
