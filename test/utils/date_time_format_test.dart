import 'package:flutter_test/flutter_test.dart';

import 'package:anc_fabrics/utils/date_time_format.dart';

void main() {
  group('formatEventTimestamp', () {
    test('formats a morning time with a leading-zero 12-hour hour', () {
      expect(
        formatEventTimestamp(DateTime(2023, 10, 16, 9, 12)),
        'Oct 16, 2023 - 09:12 AM',
      );
    });

    test('formats an afternoon time in PM', () {
      expect(
        formatEventTimestamp(DateTime(2023, 10, 14, 14, 45)),
        'Oct 14, 2023 - 02:45 PM',
      );
    });

    test('formats noon as 12:00 PM', () {
      expect(
        formatEventTimestamp(DateTime(2023, 10, 14, 12, 0)),
        'Oct 14, 2023 - 12:00 PM',
      );
    });

    test('formats midnight as 12:00 AM', () {
      expect(
        formatEventTimestamp(DateTime(2023, 10, 14, 0, 0)),
        'Oct 14, 2023 - 12:00 AM',
      );
    });

    test('pads single-digit minutes', () {
      expect(
        formatEventTimestamp(DateTime(2023, 10, 14, 13, 5)),
        'Oct 14, 2023 - 01:05 PM',
      );
    });
  });

  group('formatMonthDay', () {
    test('formats a date without the year', () {
      expect(formatMonthDay(DateTime(2023, 10, 1)), 'Oct 1');
    });

    test('formats a different month and day', () {
      expect(formatMonthDay(DateTime(2023, 8, 2)), 'Aug 2');
    });
  });
}
