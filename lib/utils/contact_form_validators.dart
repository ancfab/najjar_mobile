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

/// Matches phone numbers made up of an optional leading `+` plus digits,
/// spaces, hyphens, and parentheses — permissive enough to accept any
/// country's display format (including an embedded country code like
/// `+1 (555) 902-3481`) without enforcing one specific national pattern.
final RegExp _phoneAllowedCharacters = RegExp(r'^\+?[0-9\s\-()]+$');

/// Validates a phone number field: rejects blank input, characters other
/// than digits/`+`/spaces/hyphens/parentheses, and digit counts outside the
/// 7-15 range international numbers (with their country code, if included)
/// fall into.
String? validatePhoneField(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Please enter your phone number.';
  }
  final digitCount = trimmed.replaceAll(RegExp(r'[^0-9]'), '').length;
  if (!_phoneAllowedCharacters.hasMatch(trimmed) ||
      digitCount < 7 ||
      digitCount > 15) {
    return 'Please enter a valid phone number.';
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
