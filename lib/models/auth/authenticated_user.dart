/// Purpose: The authenticated user's identity as returned by the ANC
/// login response.
///
/// Responsibilities:
/// - Parse the `user` object of a login response, validating required
///   fields rather than silently coercing malformed data.
///
/// Must not:
/// - Interpret or act on [bcCustomerNo] — it is an opaque Business Central
///   identifier owned entirely by the ANC API; the app must never use it to
///   contact Business Central directly.
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.username,
    required this.phone,
    required this.country,
    required this.clientId,
    required this.bcCustomerNo,
    required this.mustChangePassword,
    this.avatarUrl,
  });

  final int id;
  final String username;
  final String phone;
  final String country;
  final String clientId;

  /// Opaque Business Central customer reference, if the ANC API has one on
  /// file for this user. May be absent or null.
  final String? bcCustomerNo;

  final bool mustChangePassword;

  /// The user's avatar image URL, if one has been uploaded (see
  /// `POST /auth/me/avatar`). Absent or null when no avatar has been set —
  /// there is no separate remove-avatar endpoint, so this can only change
  /// from null to a URL, or from one URL to a replacement URL, never back
  /// to null. Opaque: never parsed, rewritten, or have query parameters
  /// appended — the ANC API owns its exact form.
  final String? avatarUrl;

  /// Parses the `user` object of a login response.
  ///
  /// Throws a [FormatException] — never an uncontrolled cast error — when a
  /// required field is missing or has the wrong type.
  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) {
      throw const FormatException('AuthenticatedUser.id missing or not an int');
    }

    final username = json['username'];
    if (username is! String || username.isEmpty) {
      throw const FormatException(
        'AuthenticatedUser.username missing or empty',
      );
    }

    final phone = json['phone'];
    if (phone is! String || phone.isEmpty) {
      throw const FormatException('AuthenticatedUser.phone missing or empty');
    }

    final country = json['country'];
    if (country is! String || country.isEmpty) {
      throw const FormatException('AuthenticatedUser.country missing or empty');
    }

    final clientId = json['client_id'];
    if (clientId is! String || clientId.isEmpty) {
      throw const FormatException(
        'AuthenticatedUser.client_id missing or empty',
      );
    }

    final bcCustomerNo = json['bc_customer_no'];
    if (bcCustomerNo != null && bcCustomerNo is! String) {
      throw const FormatException(
        'AuthenticatedUser.bc_customer_no was not a string',
      );
    }

    final mustChangePassword = json['must_change_password'];
    if (mustChangePassword is! bool) {
      throw const FormatException(
        'AuthenticatedUser.must_change_password missing or not a bool',
      );
    }

    final avatarUrl = json['avatar_url'];
    if (avatarUrl != null && avatarUrl is! String) {
      throw const FormatException(
        'AuthenticatedUser.avatar_url was not a string',
      );
    }

    return AuthenticatedUser(
      id: id,
      username: username,
      phone: phone,
      country: country,
      clientId: clientId,
      bcCustomerNo: bcCustomerNo as String?,
      mustChangePassword: mustChangePassword,
      avatarUrl: avatarUrl as String?,
    );
  }
}
