/// Purpose: The customer-profile display fields this app persists locally
/// on-device — full name, email, company, and business address — since no
/// confirmed backend endpoint currently returns or accepts them (see
/// `ProfileService`/`UnavailableProfileService`). Until this phase, these
/// fields were always shown from `kMockUserProfile`; a
/// `LocalCustomerProfileStore` now persists whatever the user actually
/// saves in `EditProfileScreen`, scoped per authenticated account.
///
/// Responsibilities:
/// - Hold exactly these four fields.
/// - Serialize to and parse from one JSON envelope for local persistence.
/// - Tolerate a missing or wrong-typed field by treating it as an empty
///   string rather than throwing, so a partially-written or future-format
///   record never makes an otherwise-usable profile unreadable — this is
///   locally-owned display data, not a security- or contract-sensitive
///   payload like `AuthSession`.
///
/// Must not:
/// - Hold authentication/session fields (`username`, `phone`, `country`,
///   `client_id`, `bc_customer_no`, `avatar_url`) — those remain
///   `AuthSession`'s responsibility and are never duplicated here.
/// - Hold Business Central financial fields (`CustomerDetails` owns those,
///   and is deliberately never persisted at all).
class LocalCustomerProfile {
  const LocalCustomerProfile({
    required this.fullName,
    required this.email,
    required this.company,
    required this.businessAddress,
  });

  final String fullName;
  final String email;
  final String company;
  final String businessAddress;

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'email': email,
    'company': company,
    'business_address': businessAddress,
  };

  /// Parses a persisted profile envelope. Never throws: a missing or
  /// wrong-typed field simply resolves to an empty string (see the class
  /// doc comment) — only [LocalCustomerProfileStore] decides that a whole
  /// stored entry is unreadable (not valid JSON, or not a JSON object).
  factory LocalCustomerProfile.fromJson(Map<String, dynamic> json) {
    return LocalCustomerProfile(
      fullName: _stringOrEmpty(json['full_name']),
      email: _stringOrEmpty(json['email']),
      company: _stringOrEmpty(json['company']),
      businessAddress: _stringOrEmpty(json['business_address']),
    );
  }

  static String _stringOrEmpty(Object? value) => value is String ? value : '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCustomerProfile &&
          fullName == other.fullName &&
          email == other.email &&
          company == other.company &&
          businessAddress == other.businessAddress);

  @override
  int get hashCode => Object.hash(fullName, email, company, businessAddress);
}
