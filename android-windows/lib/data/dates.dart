// Dates the way Margin stores and shows them.
//
// Stored: ISO 8601 in UTC without fractional seconds ("2026-11-03T08:00:00Z"),
// which is what Swift's JSONEncoder (.iso8601) writes and accepts.
// Shown: German, Monday first.

String two(int n) => n.toString().padLeft(2, '0');

String isoDate(DateTime date) {
  final u = date.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

DateTime? parseIso(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

/// Whole calendar days from [from] to [to] (negative if [to] is earlier).
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) => startOfDay(d).subtract(Duration(days: d.weekday - 1));

const weekdayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

abstract final class Fmt {
  /// "3. November"
  static String dayMonth(DateTime d) => '${d.day}. ${monthNames[d.month - 1]}';

  /// "Di., 3. Nov."
  static String shortDay(DateTime d) =>
      '${weekdayShort[d.weekday - 1]}., ${d.day}. ${monthNames[d.month - 1].substring(0, 3)}.';

  /// "Dienstag, 3. November"
  static String longDay(DateTime d) => '${weekdayNames[d.weekday - 1]}, ${dayMonth(d)}';

  /// "03.11.2026"
  static String numeric(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

  /// "08:15"
  static String time(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  /// Minutes since midnight → "08:15"
  static String clock(int minutes) => '${two(minutes ~/ 60)}:${two(minutes % 60)}';

  /// "Heute", "Morgen", "Gestern", "In 4 Tagen", "Vor 2 Tagen" or the date.
  static String relativeDay(DateTime d, {DateTime? now}) {
    final days = daysBetween(now ?? DateTime.now(), d);
    if (days == 0) return 'Heute';
    if (days == 1) return 'Morgen';
    if (days == 2) return 'Übermorgen';
    if (days == -1) return 'Gestern';
    if (days > 2 && days < 7) return weekdayNames[d.weekday - 1];
    if (days < 0 && days > -7) return 'Vor ${-days} Tagen';
    return shortDay(d);
  }
}
