/// Normalizes a phone number into the digits-only, country-code-included
/// form WhatsApp deep links expect (e.g. `whatsapp://send?phone=<digits>`
/// or `https://wa.me/<digits>`).
///
/// Accepts numbers in international display format (e.g.
/// `+961 3 123 456` or `+971-50-123-4567`) and strips the leading `+` plus
/// any spaces, hyphens, parentheses, or other formatting, leaving only
/// digits — the country code is never removed because it's part of the
/// digit sequence.
///
/// Returns `null` for `null`, empty, or non-international input (numbers
/// without a leading `+`) rather than guessing a country code for what
/// might be a local number.
String? normalizeWhatsAppNumber(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (!trimmed.startsWith('+')) return null;

  final digitsOnly = trimmed.substring(1).replaceAll(RegExp(r'[^0-9]'), '');
  // E.164 international numbers are 8-15 digits (country code + subscriber
  // number); shorter/longer results indicate malformed input.
  if (digitsOnly.length < 8 || digitsOnly.length > 15) return null;

  return digitsOnly;
}

/// Normalizes [raw] into the digits-only WhatsApp form, using [dialCode]
/// (e.g. `+963`) as the country code when [raw] is written locally rather
/// than internationally — which is how most verified regional contact
/// numbers are stored (e.g. Syria's `0989204480`).
///
/// An already-international [raw] (leading `+`) keeps its own country code
/// and ignores [dialCode] entirely, so a number verified for one country is
/// never rewritten into another. A local number's single leading trunk `0`
/// is dropped before [dialCode] is applied, per E.164.
///
/// Returns `null` when [raw] is unusable, or when it is local and no
/// [dialCode] is known — a country code is never guessed.
String? normalizeWhatsAppNumberWithDialCode(String? raw, String? dialCode) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('+')) return normalizeWhatsAppNumber(trimmed);

  if (dialCode == null) return null;
  final codeDigits = dialCode.replaceAll(RegExp(r'[^0-9]'), '');
  if (codeDigits.isEmpty) return null;

  var localDigits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (localDigits.isEmpty) return null;
  // A single leading trunk prefix is local-dialing notation only; E.164
  // drops it. Deliberately only one, so a number that legitimately begins
  // with 0 after the trunk digit keeps it.
  if (localDigits.startsWith('0')) localDigits = localDigits.substring(1);
  if (localDigits.isEmpty) return null;

  return normalizeWhatsAppNumber('+$codeDigits$localDigits');
}

/// Normalizes a phone number into the form suitable for a `tel:` URI.
///
/// Unlike [normalizeWhatsAppNumber], a leading `+` (and the international
/// country code it precedes) is preserved rather than stripped, since
/// `tel:` URIs may include it. Spaces, hyphens, parentheses, and other
/// display-only separators are removed either way. A number with no
/// leading `+` is treated as local and returned digits-only — no country
/// code is ever guessed or added.
///
/// Returns `null` for `null`, empty, or otherwise unusable input (e.g. a
/// bare `+` or a string with no digits at all).
String? normalizePhoneNumberForTel(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final hasLeadingPlus = trimmed.startsWith('+');
  final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.length < 3) return null;

  return hasLeadingPlus ? '+$digitsOnly' : digitsOnly;
}
