// Fake in-memory ContactSupportService for tests that exercise the Contact
// Us submission flow without depending on a real backend, which doesn't
// exist yet.

import 'dart:async';

import 'package:anc_fabrics/services/contact_support_service.dart';

class FakeContactSupportService implements ContactSupportService {
  FakeContactSupportService({this.result, this.pending});

  /// A [ContactSubmissionResult] to resolve with, or an [Exception] to
  /// throw. Ignored when [pending] is set. Mutable so a test can change
  /// the outcome between submissions (e.g. to exercise a retry-after
  /// failure flow).
  Object? result;

  /// When set, `submit` awaits this instead of resolving immediately —
  /// lets tests hold a submission "in flight" to observe loading state and
  /// the duplicate-submission guard.
  final Completer<ContactSubmissionResult>? pending;

  final List<ContactRequest> submittedRequests = [];

  @override
  Future<ContactSubmissionResult> submit(ContactRequest request) async {
    submittedRequests.add(request);
    if (pending != null) return pending!.future;
    if (result is Exception) throw result as Exception;
    return result as ContactSubmissionResult? ??
        ContactSubmissionResult.success;
  }
}
