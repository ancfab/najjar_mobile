// Fake in-memory ProfileService for tests that exercise the Edit Profile
// "Save Changes" flow without depending on a real backend, which doesn't
// exist yet.

import 'dart:async';

import 'package:anc_fabrics/services/profile_service.dart';

class FakeProfileService implements ProfileService {
  FakeProfileService({this.result, this.pending});

  /// A [ProfileUpdateResult] to resolve with, or an [Exception] to throw.
  /// Ignored when [pending] is set.
  Object? result;

  /// When set, `updateProfile` awaits this instead of resolving
  /// immediately — lets tests hold a submission "in flight" to observe
  /// loading state and the duplicate-submission guard.
  final Completer<ProfileUpdateResult>? pending;

  final List<ProfileUpdateRequest> submittedRequests = [];

  @override
  Future<ProfileUpdateResult> updateProfile(
    ProfileUpdateRequest request,
  ) async {
    submittedRequests.add(request);
    if (pending != null) return pending!.future;
    if (result is Exception) throw result as Exception;
    return result as ProfileUpdateResult? ??
        const ProfileUpdateResult(ProfileUpdateOutcome.success);
  }
}
