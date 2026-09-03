import 'authenticated_user.dart';

/// Purpose: Parsed `POST /api/auth/login` HTTP 200 success body.
///
/// Responsibilities:
/// - Validate and expose the opaque session [token] exactly as received.
/// - Normalize the response's duplicated `must_change_password` flag into
///   one deterministic value (see [_normalizeMustChangePassword]).
///
/// Must not:
/// - Split, decode, or otherwise transform [token] — it is an opaque
///   Sanctum personal access token, not a JWT, and has no client-derivable
///   expiry.
/// - Trigger or imply a forced password-change screen.
class LoginResponse {
  const LoginResponse({
    required this.token,
    required this.mustChangePassword,
    required this.user,
    this.customerDetails,
  });

  /// Opaque Sanctum personal access token, stored and sent back exactly as
  /// received — never split, decoded, or normalized.
  final String token;

  /// Normalized non-blocking session metadata: the top-level
  /// `must_change_password` value, falling back to the nested user's value
  /// only when the top-level field is absent (see
  /// [_normalizeMustChangePassword]).
  ///
  /// parsed and stored as session metadata only — it must not gate
  /// navigation or drive a forced password-change screen until such an
  /// endpoint exists.
  final bool mustChangePassword;

  final AuthenticatedUser user;

  /// The raw `customer_details` object the backend embeds on login when the
  /// account is linked to a Business Central customer (name, address,
  /// contact info, balance figures — field names vary per BC tenant), or
  /// `null` when absent, disabled server-side, or not a JSON object.
  /// Deliberately lenient: this is enrichment used to seed the local
  /// customer profile (see `AuthService.login`), so a missing or
  /// oddly-shaped value must never fail an otherwise valid login.
  final Map<String, dynamic>? customerDetails;

  /// Parses a login success body.
  ///
  /// Throws a [FormatException] — never including [token]'s value — when
  /// required data is missing or malformed.
  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('LoginResponse.token missing or empty');
    }

    final userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const FormatException('LoginResponse.user missing or malformed');
    }
    final user = AuthenticatedUser.fromJson(userJson);

    final customerDetailsJson = json['customer_details'];

    return LoginResponse(
      token: token,
      mustChangePassword: _normalizeMustChangePassword(json, user),
      user: user,
      customerDetails: customerDetailsJson is Map<String, dynamic>
          ? customerDetailsJson
          : null,
    );
  }

  /// Prefers the top-level `must_change_password`; falls back to the
  /// nested user's value only as defensive compatibility when the
  /// top-level field is entirely absent. When both are present and
  /// disagree, the top-level value always wins.
  static bool _normalizeMustChangePassword(
    Map<String, dynamic> json,
    AuthenticatedUser user,
  ) {
    final topLevel = json['must_change_password'];
    if (topLevel is bool) return topLevel;
    return user.mustChangePassword;
  }
}
