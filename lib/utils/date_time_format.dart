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

/// Formats [dateTime] as `"MMM d"` (e.g. `"Oct 16"`), with no year — used
/// for compact chart axis labels and range subtitles where the year is
/// shown separately (see [formatDateOnly]).
///
/// TODO: Switch to locale-aware formatting (e.g. via `package:intl`) once
/// the app's locale requirements are confirmed — this assumes a fixed
/// `en_US`-style format.
String formatMonthDay(DateTime dateTime) {
  final month = _monthAbbreviations[dateTime.month - 1];
  return '$month ${dateTime.day}';
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

/// Formats [dateTime] (converted to local time) as `"yyyy-MM-dd HH:mm"`
/// (e.g. `"2026-07-31 12:30"`) — a locale-neutral, always-LTR numeric
/// timestamp used for technical scan records (Scan Stock's Recent Scan card
/// and Scan History list) where a month name would need translation but a
/// numeric date does not.
String formatCompactLocalTimestamp(DateTime dateTime) {
  final local = dateTime.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
