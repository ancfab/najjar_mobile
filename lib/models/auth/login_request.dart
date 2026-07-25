/// Purpose: Exact JSON payload sent to `POST /api/auth/login`.
///
/// Responsibilities:
/// - Serialize the fields the ANC API's login contract requires, using its
///   exact snake_case keys.
///
/// Must not:
/// - Be logged, cached, or persisted — it carries the plaintext [password]
///   for the single duration of the login request only.
/// - Gain a `toString()` override, to avoid accidentally printing
///   [password] via debug tooling that calls it implicitly.
class LoginRequest {
  const LoginRequest({
    required this.country,
    required this.phone,
    required this.username,
    required this.clientId,
    required this.password,
  });

  /// ANC API country code: one of `AE`, `IQ`, `SY`, `LB`, `OM`.
  final String country;

  /// E.164 phone number, e.g. `+96890000000`.
  final String phone;

  final String username;

  /// Fixed distributor client id, supplied by `ApiConfig` via
  /// `AuthService` — never a LoginScreen/user-entered value.
  final String clientId;

  /// Plaintext password, sent exactly as entered — never trimmed or
  /// otherwise modified.
  final String password;

  /// Serializes to the ANC API's exact wire field names.
  Map<String, dynamic> toJson() => {
    'country': country,
    'phone': phone,
    'username': username,
    'client_id': clientId,
    'password': password,
  };
}
