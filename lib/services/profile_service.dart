/// Typed payload for an Edit Profile "Save Changes" submission, containing
/// only the fields collected by the Edit Profile form.
class ProfileUpdateRequest {
  const ProfileUpdateRequest({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.company,
    required this.businessAddress,
  });

  /// Trimmed full name.
  final String fullName;

  /// Trimmed email address.
  final String email;

  /// Trimmed phone number.
  final String phone;

  /// Trimmed company name.
  final String company;

  /// Trimmed business address.
  final String businessAddress;
}

/// How a [ProfileService.updateProfile] attempt resolved.
enum ProfileUpdateOutcome {
  /// The backend accepted the updated profile.
  success,

  /// The backend was reached but rejected the request, or the request
  /// failed to reach it (network/timeout/unexpected exception).
  failure,

  /// No real backend integration exists yet, so no update was attempted.
  unavailable,
}

class ProfileUpdateResult {
  const ProfileUpdateResult(this.outcome, {this.message});

  final ProfileUpdateOutcome outcome;

  /// Optional user-safe message describing the outcome — never a stack
  /// trace, HTTP response body, or other backend implementation detail.
  final String? message;

  bool get succeeded => outcome == ProfileUpdateOutcome.success;

  static const ProfileUpdateResult unavailable = ProfileUpdateResult(
    ProfileUpdateOutcome.unavailable,
  );
}

/// Submits Edit Profile form changes to the profile backend.
abstract class ProfileService {
  Future<ProfileUpdateResult> updateProfile(ProfileUpdateRequest request);
}

/// TODO(api): No real profile-update backend exists anywhere in this
/// project yet — there is no API base URL, request/response contract, or
/// authentication requirement documented or implemented for it. This
/// implementation is NOT production-ready: it performs no network call and
/// always reports [ProfileUpdateOutcome.unavailable] rather than pretending
/// the change was saved. Replace it with a real [ProfileService]
/// implementation once the profile update endpoint and payload contract
/// are confirmed by product/backend.
class UnavailableProfileService implements ProfileService {
  const UnavailableProfileService();

  @override
  Future<ProfileUpdateResult> updateProfile(
    ProfileUpdateRequest request,
  ) async {
    return ProfileUpdateResult.unavailable;
  }
}
