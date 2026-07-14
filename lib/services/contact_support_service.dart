import '../models/contact_subject.dart';
import '../models/support_region.dart';

/// Typed payload for a Contact Us submission, containing only the fields a
/// support/ticketing backend would plausibly need.
class ContactRequest {
  const ContactRequest({
    required this.name,
    required this.email,
    required this.subject,
    required this.message,
    required this.regionId,
  });

  /// Trimmed customer name.
  final String name;

  /// Trimmed customer email.
  final String email;

  /// Stable subject identifier (the enum value itself) — never the
  /// translated display label, so the backend never has to parse UI copy.
  final ContactSubject subject;

  /// Trimmed message body.
  final String message;

  /// The Support region the customer was viewing when they opened this
  /// form.
  final SupportRegionId regionId;
}

/// How a [ContactSupportService.submit] attempt resolved.
enum ContactSubmissionOutcome {
  /// The backend accepted the request.
  success,

  /// The backend was reached but rejected the request, or the request
  /// failed to reach it (network/timeout/unexpected exception).
  failure,

  /// No real backend integration exists yet, so no submission was
  /// attempted.
  unavailable,
}

class ContactSubmissionResult {
  const ContactSubmissionResult(this.outcome, {this.message});

  final ContactSubmissionOutcome outcome;

  /// Optional user-safe message describing the outcome — never a stack
  /// trace, HTTP response body, or other backend implementation detail.
  final String? message;

  bool get succeeded => outcome == ContactSubmissionOutcome.success;

  static const ContactSubmissionResult success = ContactSubmissionResult(
    ContactSubmissionOutcome.success,
  );

  static const ContactSubmissionResult unavailable = ContactSubmissionResult(
    ContactSubmissionOutcome.unavailable,
  );
}

/// Submits a Contact Us request to the support/ticketing backend.
abstract class ContactSupportService {
  Future<ContactSubmissionResult> submit(ContactRequest request);
}

/// TODO: No real Contact Us / support-ticketing backend exists anywhere in
/// this project yet — there is no API base URL, request/response
/// contract, ticketing-provider identity, or authentication requirement
/// documented or implemented for it. This implementation is NOT
/// production-ready: it performs no network call and always reports
/// [ContactSubmissionOutcome.unavailable] rather than pretending a
/// message was sent. Replace it with a real [ContactSupportService]
/// implementation once the backend contract (endpoint, payload shape,
/// auth, and success/failure response format) is supplied by
/// product/backend. Real ticket creation is blocked until then.
class UnavailableContactSupportService implements ContactSupportService {
  const UnavailableContactSupportService();

  @override
  Future<ContactSubmissionResult> submit(ContactRequest request) async {
    return ContactSubmissionResult.unavailable;
  }
}
