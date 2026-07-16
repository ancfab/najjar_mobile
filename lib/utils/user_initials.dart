/// Derives up to two uppercase initials from a full name (e.g.
/// `"Alex Sterling"` -> `"AS"`), for use in avatar badges where only a name
/// is available (no photo).
///
/// Falls back to [fallback] when [fullName] is empty or blank.
String userInitials(String fullName, {String fallback = 'JD'}) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return fallback;

  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  final initials = (first + last).toUpperCase();
  return initials.isEmpty ? fallback : initials;
}
