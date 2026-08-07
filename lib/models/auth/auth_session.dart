import 'authenticated_user.dart';
import 'login_response.dart';

/// Purpose: The authenticated ANC API session data this app persists after
/// a successful real login.
///
/// Responsibilities:
/// - Hold exactly the fields a resumed session needs: the opaque Bearer
///   [token] and the identity fields from the login response.
/// - Serialize to and parse from one versioned JSON envelope (see
///   [schemaVersion]) for secure-storage persistence.
///
/// Must not:
/// - Hold the account password or the original `LoginRequest`.
/// - Split, decode, or otherwise interpret [token] — it is an opaque
///   Sanctum personal access token, not a JWT.
/// - Interpret [bcCustomerNo] or construct any Business Central request
///   from it.
/// - Expose [token] through [toString].
class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.username,
    required this.phone,
    required this.country,
    required this.clientId,
    this.bcCustomerNo,
    required this.mustChangePassword,
    this.avatarUrl,
  });

  /// Opaque Sanctum personal access token, persisted and restored exactly
  /// as received — never split, decoded, or normalized. May contain a `|`
  /// character; that is a normal, unremarkable part of the opaque value.
  final String token;

  final int userId;
  final String username;
  final String phone;
  final String country;
  final String clientId;

  /// Opaque Business Central customer reference, if the ANC API has one on
  /// file for this user. May be absent or null.
  final String? bcCustomerNo;

  /// Normalized, non-blocking session metadata carried over from
  /// [LoginResponse.mustChangePassword].
  ///
  /// TODO(api): Remains non-blocking because no password-change endpoint
  /// exists yet — this flag must not gate navigation or a forced
  /// password-change screen until one does.
  final bool mustChangePassword;

  /// The user's avatar image URL, if one has been uploaded — see
  /// `AuthenticatedUser.avatarUrl`, which this mirrors. Refreshed the same
  /// way every other identity field is: via [fromAuthenticatedUser] after
  /// `GET /auth/me`, `PATCH /auth/me`, or `POST /auth/me/avatar`.
  final String? avatarUrl;

  /// The schema version this class reads and writes. Bump this and add
  /// explicit migration/rejection logic in [fromJson] if the persisted
  /// shape ever changes.
  static const int schemaVersion = 1;

  /// Maps a successful login response onto the session that must persist.
  /// Reuses [LoginResponse]'s already-validated fields rather than
  /// re-parsing anything.
  factory AuthSession.fromLoginResponse(LoginResponse response) {
    final user = response.user;
    return AuthSession(
      token: response.token,
      userId: user.id,
      username: user.username,
      phone: user.phone,
      country: user.country,
      clientId: user.clientId,
      bcCustomerNo: user.bcCustomerNo,
      mustChangePassword: response.mustChangePassword,
      avatarUrl: user.avatarUrl,
    );
  }

  /// Refreshes an already-persisted session's identity fields from a
  /// confirmed `GET /auth/me` response, preserving [token] unchanged — that
  /// endpoint never returns a new token. Used by
  /// `AuthService.confirmSession` on cold app launch so a returning user's
  /// stored identity data never goes stale after the backend confirms the
  /// token is still valid.
  factory AuthSession.fromAuthenticatedUser({
    required String token,
    required AuthenticatedUser user,
  }) => AuthSession(
    token: token,
    userId: user.id,
    username: user.username,
    phone: user.phone,
    country: user.country,
    clientId: user.clientId,
    bcCustomerNo: user.bcCustomerNo,
    mustChangePassword: user.mustChangePassword,
    avatarUrl: user.avatarUrl,
  );

  /// Serializes to the versioned envelope persisted by
  /// `SecureAuthSessionStore`.
  ///
  /// [avatarUrl] is included as a plain optional field (present as `null`
  /// when absent) rather than bumping [schemaVersion]: it is a purely
  /// additive field an older-schema reader would simply not have written,
  /// and [fromJson] already treats a missing key the same as an explicit
  /// `null` — no migration or rejection logic is needed for it.
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'token': token,
    'user_id': userId,
    'username': username,
    'phone': phone,
    'country': country,
    'client_id': clientId,
    'bc_customer_no': bcCustomerNo,
    'must_change_password': mustChangePassword,
    'avatar_url': avatarUrl,
  };

  /// Parses a persisted session envelope.
  ///
  /// Throws a [FormatException] — never including [token]'s value, and
  /// never an uncontrolled cast error — when the schema version is
  /// unsupported or a required field is missing/malformed. Callers that
  /// treat "no valid session" and "malformed data" the same way (as
  /// `SecureAuthSessionStore.read` does) should catch [FormatException]
  /// around this call.
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'];
    if (schemaVersion is! int || schemaVersion != AuthSession.schemaVersion) {
      throw const FormatException('AuthSession.schema_version unsupported');
    }

    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('AuthSession.token missing or empty');
    }

    final userId = json['user_id'];
    if (userId is! int) {
      throw const FormatException('AuthSession.user_id missing or not an int');
    }

    final username = json['username'];
    if (username is! String || username.isEmpty) {
      throw const FormatException('AuthSession.username missing or empty');
    }

    final phone = json['phone'];
    if (phone is! String || phone.isEmpty) {
      throw const FormatException('AuthSession.phone missing or empty');
    }

    final country = json['country'];
    if (country is! String || country.isEmpty) {
      throw const FormatException('AuthSession.country missing or empty');
    }

    final clientId = json['client_id'];
    if (clientId is! String || clientId.isEmpty) {
      throw const FormatException('AuthSession.client_id missing or empty');
    }

    final bcCustomerNo = json['bc_customer_no'];
    if (bcCustomerNo != null && bcCustomerNo is! String) {
      throw const FormatException(
        'AuthSession.bc_customer_no was not a string',
      );
    }

    final mustChangePassword = json['must_change_password'];
    if (mustChangePassword is! bool) {
      throw const FormatException(
        'AuthSession.must_change_password missing or not a bool',
      );
    }

    final avatarUrl = json['avatar_url'];
    if (avatarUrl != null && avatarUrl is! String) {
      throw const FormatException('AuthSession.avatar_url was not a string');
    }

    return AuthSession(
      token: token,
      userId: userId,
      username: username,
      phone: phone,
      country: country,
      clientId: clientId,
      bcCustomerNo: bcCustomerNo as String?,
      mustChangePassword: mustChangePassword,
      avatarUrl: avatarUrl as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthSession &&
          token == other.token &&
          userId == other.userId &&
          username == other.username &&
          phone == other.phone &&
          country == other.country &&
          clientId == other.clientId &&
          bcCustomerNo == other.bcCustomerNo &&
          mustChangePassword == other.mustChangePassword &&
          avatarUrl == other.avatarUrl);

  @override
  int get hashCode => Object.hash(
    token,
    userId,
    username,
    phone,
    country,
    clientId,
    bcCustomerNo,
    mustChangePassword,
    avatarUrl,
  );

  /// Deliberately omits [token]: this must never appear in logs, crash
  /// reports, or debug tooling that calls [toString] implicitly.
  @override
  String toString() => 'AuthSession(userId: $userId, username: $username)';
}
