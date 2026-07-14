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
