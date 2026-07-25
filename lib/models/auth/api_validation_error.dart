/// Purpose: Safe parsing of the ANC API's HTTP 422 validation-error body.
///
/// Responsibilities:
/// - Parse `message` and `errors` defensively, tolerating missing, unknown,
///   or malformed shapes without throwing.
/// - Offer field-lookup helpers so callers can ask for one field's messages
///   without inspecting the raw map themselves.
///
/// Must not:
/// - Contain final user-facing wording (e.g. "incorrect password") — this
///   is a parsed data holder, not a presentation layer; the future
///   AuthService/LoginScreen decide user-facing wording.
/// - Be treated as proof of which field was actually wrong: per the ANC API
///   contract, a credential failure surfaces under `errors.username` even
///   when the username itself was correct (e.g. wrong password, a
///   deactivated account) — callers must treat that as a neutral
///   form-level error, not evidence the username specifically was invalid.
class ApiValidationError {
  const ApiValidationError({this.message, this.errors = const {}});

  /// Top-level neutral message, if present.
  final String? message;

  /// Field name to non-empty list of messages for that field. Fields with
  /// no usable (string) messages are omitted rather than stored empty.
  final Map<String, List<String>> errors;

  /// Parses a 422 response body. Accepts `Object?` because the body may not
  /// even be a JSON object (e.g. a non-JSON error page) — any shape other
  /// than a `Map` safely produces an empty, message-less instance rather
  /// than throwing.
  factory ApiValidationError.fromJson(Object? json) {
    if (json is! Map) return const ApiValidationError();

    final message = json['message'];

    final errors = <String, List<String>>{};
    final rawErrors = json['errors'];
    if (rawErrors is Map) {
      for (final entry in rawErrors.entries) {
        final field = entry.key;
        if (field is! String) continue;

        final messages = _parseMessages(entry.value);
        if (messages.isNotEmpty) errors[field] = messages;
      }
    }

    return ApiValidationError(
      message: message is String ? message : null,
      errors: errors,
    );
  }

  static List<String> _parseMessages(Object? rawMessages) {
    if (rawMessages is String) return [rawMessages];
    if (rawMessages is List) {
      return [
        for (final item in rawMessages)
          if (item is String) item,
      ];
    }
    return const [];
  }

  /// All messages for [field], or `null` if there are none.
  List<String>? messagesFor(String field) => errors[field];

  /// The first message for [field], or `null` if there are none.
  String? firstErrorFor(String field) {
    final messages = errors[field];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  /// Convenience for the one field the future LoginScreen may show inline:
  /// the first message under `errors.phone`, or `null`.
  String? get phoneError => firstErrorFor('phone');
}
