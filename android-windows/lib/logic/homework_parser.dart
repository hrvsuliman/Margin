// Reads recognised text like "Mathe: S. 34 Nr. 5a bis Freitag" and guesses
// title, subject and due date. Plain rules, no AI, works offline.
// Ported from Margin/Services/Import/HomeworkParser.swift.

import '../data/dates.dart';

class HomeworkSuggestion {
  const HomeworkSuggestion({required this.title, required this.details, this.dueDate, this.subjectName});

  final String title;
  final String details;
  final DateTime? dueDate;
  final String? subjectName;
}

abstract final class HomeworkParser {
  /// Dart weekday numbers (1 = Monday).
  static const _weekdays = {
    'montag': 1, 'dienstag': 2, 'mittwoch': 3, 'donnerstag': 4, 'freitag': 5, 'samstag': 6, 'sonntag': 7,
  };
  static final _taskWords = RegExp(
    r'(\bS\.\s?\d|\bSeite\b|\bNr\.|\bAufgabe|\bAB\b|Arbeitsblatt|\bBuch\b|\bHeft\b|lernen\b|lesen\b|schreiben\b|Vokabeln|bearbeiten)',
    caseSensitive: false,
  );

  static HomeworkSuggestion suggest(String text, List<String> subjects, {DateTime? today}) {
    final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final titleLine = lines.firstWhere((l) => _taskWords.hasMatch(l), orElse: () => lines.isEmpty ? '' : lines.first);
    final details = lines.join('\n');
    return HomeworkSuggestion(
      title: cleanTitle(titleLine),
      details: details.length > 1000 ? details.substring(0, 1000) : details,
      dueDate: dueDate(text, today ?? DateTime.now()),
      subjectName: subject(text, subjects),
    );
  }

  static String cleanTitle(String line) {
    var title = line;
    for (final prefix in ['Hausaufgaben:', 'Hausaufgabe:', 'HA:', 'HA ']) {
      if (title.toLowerCase().startsWith(prefix.toLowerCase())) {
        title = title.substring(prefix.length).trim();
      }
    }
    if (title.length <= 70) return title;
    final cut = title.substring(0, 70);
    final space = cut.lastIndexOf(' ');
    return '${space > 0 ? cut.substring(0, space) : cut} …';
  }

  /// Explicit date first ("bis 12.11."), then a weekday ("bis Freitag"),
  /// then "übermorgen", "morgen", "nächste Woche".
  static DateTime? dueDate(String text, DateTime today) {
    final lower = text.toLowerCase();
    final start = startOfDay(today);

    final explicit = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{2,4})?').firstMatch(lower);
    if (explicit != null) {
      final day = int.parse(explicit.group(1)!);
      final month = int.parse(explicit.group(2)!);
      if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
        final yearText = explicit.group(3);
        var year = start.year;
        if (yearText != null) {
          final parsed = int.parse(yearText);
          year = parsed < 100 ? 2000 + parsed : parsed;
        }
        var date = DateTime(year, month, day);
        if (yearText == null && date.isBefore(start)) date = DateTime(year + 1, month, day);
        if (!date.isBefore(start)) return date;
      }
    }

    final names = _weekdays.keys.join('|');
    final weekday = RegExp('(?:bis|zum|zur|für|fuer|am)\\s+(?:(?:den|nächsten|naechsten|kommenden)\\s+)?($names)')
        .firstMatch(lower);
    if (weekday != null) {
      final target = _weekdays[weekday.group(1)!]!;
      var days = (target - start.weekday + 7) % 7;
      if (days == 0) days = 7;
      return addDays(start, days);
    }
    if (lower.contains('übermorgen') || lower.contains('uebermorgen')) return addDays(start, 2);
    if (RegExp(r'(^|[^\p{L}])morgen($|[^\p{L}])', unicode: true).hasMatch(lower)) return addDays(start, 1);
    if (lower.contains('nächste woche') || lower.contains('naechste woche')) return addDays(start, 7);
    return null;
  }

  /// A subject named in the text, also by a short form ("Mathe" → "Mathematik").
  static String? subject(String text, List<String> subjects) {
    final lower = text.toLowerCase();
    final words = lower.split(RegExp(r'[^\p{L}]+', unicode: true)).where((w) => w.length >= 4).toList();
    for (final subject in subjects) {
      final name = subject.toLowerCase();
      if (name.isEmpty) continue;
      if (lower.contains(name) || words.any(name.startsWith)) return subject;
    }
    return null;
  }
}
