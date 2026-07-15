const List<String> _monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [dateTime] as `"MMM d, yyyy"` (e.g. `"Oct 16, 2023"`), date-only
/// with no time component.
///
/// TODO: Switch to locale-aware formatting (e.g. via `package:intl`) once
/// the app's locale requirements are confirmed — this assumes a fixed
/// `en_US`-style format.
String formatDateOnly(DateTime dateTime) {
  final month = _monthAbbreviations[dateTime.month - 1];
  return '$month ${dateTime.day}, ${dateTime.year}';
}

/// Formats [dateTime] as `"MMM d, yyyy - hh:mm a"` (e.g. `"Oct 16, 2023 -
/// 09:12 AM"`), with a 12-hour, leading-zero hour and no seconds or
/// timezone.
///
/// No date-formatting helper (or `package:intl`) existed anywhere in the app
/// before this — mirrors [formatCurrency] in `currency.dart` as the one
/// shared place that turns a raw value into this specific display text,
/// rather than duplicating it across widgets.
///
/// TODO: Switch to locale-aware formatting (e.g. via `package:intl`) once
/// the app's locale requirements are confirmed — this assumes a fixed
/// `en_US`-style format.
String formatEventTimestamp(DateTime dateTime) {
  final hour24 = dateTime.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  final hour = hour12.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');

  return '${formatDateOnly(dateTime)} - $hour:$minute $period';
}
