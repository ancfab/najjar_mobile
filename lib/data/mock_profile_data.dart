import '../models/user_profile.dart';

// Mock Edit Profile display/prefill data, kept isolated from the rest of
// the app's mock signed-in user (see `kCurrentUserName` in mock_user.dart)
// so it can be swapped for a real profile source independently.
//
// TODO(api): Replace the isolated mock profile with the authenticated user's
// profile after the profile-fetch endpoint and response contract are
// confirmed.
const UserProfile kMockUserProfile = UserProfile(
  ancId: '88219',
  fullName: 'Alexander Mitchell',
  email: 'alex.mitchell@vanguard-logistics.com',
  phone: '+1 (555) 902-3481',
  company: 'Vanguard Global Logistics',
  businessAddress: '450 Fashion Ave, Suite 1205, New York, NY 10123',
  profileUpdatedLabel: 'Profile updated 2 days ago',
);
