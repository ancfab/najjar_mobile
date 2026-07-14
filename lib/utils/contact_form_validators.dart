import '../models/contact_subject.dart';

/// Validates a required text field (e.g. name, message body): rejects
/// `null`, empty, and whitespace-only input. Shared by every Contact Us
/// field with this same "required, non-blank" shape so the trimming/empty
/// check isn't duplicated per field.
String? validateRequiredField(String? value, String requiredMessage) {
  if (value == null || value.trim().isEmpty) {
    return requiredMessage;
  }
  return null;
}

/// Matches a non-space local part, an `@`, and a domain containing a dot —
/// enough to catch a missing `@`, missing local part, or missing domain
/// without attempting a full RFC 5322 implementation that could reject
/// ordinary valid addresses.
final RegExp emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmailField(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Please enter your work email.';
  }
  if (!emailPattern.hasMatch(trimmed)) {
    return 'Please enter a valid email address.';
  }
  return null;
}

/// Requires an explicit subject selection — the dropdown's placeholder
/// hint ("Select a subject") is not itself a selectable value, so a `null`
/// selection is the only invalid state to check for here.
String? validateSubjectField(ContactSubject? value) {
  if (value == null) {
    return 'Please select a subject.';
  }
  return null;
}
