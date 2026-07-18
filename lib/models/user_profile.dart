/// Display data for the Edit Profile screen's avatar/client-info section
/// and prefilled form fields.
class UserProfile {
  const UserProfile({
    required this.ancId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.company,
    required this.businessAddress,
    required this.profileUpdatedLabel,
  });

  /// Client identifier shown as "ANC ID: #`ancId`".
  final String ancId;
  final String fullName;
  final String email;
  final String phone;
  final String company;
  final String businessAddress;

  /// Pre-formatted "last updated" label (e.g. "Profile updated 2 days
  /// ago"), matching how the rest of this app keeps mock display strings
  /// pre-formatted rather than deriving them from a raw DateTime.
  final String profileUpdatedLabel;
}
