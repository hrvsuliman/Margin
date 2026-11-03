import 'package:flutter/material.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import 'exam_editor.dart';
import 'home.dart';
import 'tasks_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Today's lessons, what's due and the next exams. Only sections with content are shown.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Heute'), actions: shellActions(context)),
        body: StoreBuilder(builder: (context, store) {
          final now = DateTime.now();
          final today = startOfDay(now);
          final holiday = store.holidays.where((h) => h.contains(today)).firstOrNull;
          final lessons = holiday == null ? store.lessons.where((l) => l.weekday == now.weekday).toList() : <Lesson>[];
          final due = store.tasks.where((t) {
            final d = t.dueDate;
            return !t.isDone && d != null && daysBetween(today, d) <= 1;
          }).toList()
            ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
          final exams = store.exams.where((e) {
            final days = daysBetween(today, e.date);
            return days >= 0 && days <= 14;
          }).toList();

          return PageBody(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Text(Fmt.longDay(now), style: TextStyle(color: context.colors.secondaryInk, fontSize: 15)),
            ),
            if (holiday != null) ...[
              const SectionTitle('Frei'),
              Group(children: [ListTile(leading: const Icon(Icons.beach_access_outlined), title: Text(holiday.name))]),
            ],
            if (lessons.isNotEmpty) ...[
              const SectionTitle('Stundenplan'),
              Group(children: [for (final lesson in lessons) _LessonTile(lesson, now: now)]),
            ],
            if (due.isNotEmpty) ...[
              SectionTitle('Fällig', trailing: Text('${due.length}', style: TextStyle(color: context.colors.secondaryInk))),
              Group(children: [for (final task in due) TaskTile(task)]),
            ],
            if (exams.isNotEmpty) ...[
              const SectionTitle('Prüfungen'),
              Group(children: [
                for (final exam in exams)
                  ListTile(
                    leading: SubjectDot(store.subject(exam.subject)?.colorKey, size: 12),
                    title: Text(store.examTitle(exam)),
                    subtitle: Text(_examDays(exam.date, today)),
                    onTap: () => openExam(context, exam),
                  ),
              ]),
            ],
            if (lessons.isEmpty && due.isEmpty && exams.isEmpty && holiday == null)
              const EmptyState(
                icon: Icons.wb_sunny_outlined,
                title: 'Nichts fällig',
                message: 'Heute stehen keine Stunden, Aufgaben oder Prüfungen an.',
              ),
          ]);
        }),
      );

  static String _examDays(DateTime date, DateTime today) {
    final days = daysBetween(today, date);
    if (days == 0) return 'Heute';
    if (days == 1) return 'Morgen';
    return 'In $days Tagen · ${Fmt.dayMonth(date)}';
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile(this.lesson, {required this.now});
  final Lesson lesson;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final subject = store.subject(lesson.subject);
    final minute = now.hour * 60 + now.minute;
    final running = minute >= lesson.startMinute && minute < lesson.endMinute;
    final room = lesson.room.isNotEmpty ? lesson.room : (subject?.room ?? '');
    return ListTile(
      leading: SubjectDot(subject?.colorKey, size: 12),
      title: Text(subject?.name ?? 'Stunde', style: TextStyle(fontWeight: running ? FontWeight.w700 : null)),
      subtitle: Text([
        '${Fmt.clock(lesson.startMinute)}–${Fmt.clock(lesson.endMinute)}',
        if (room.isNotEmpty) room,
        if (running) 'läuft',
      ].join(' · ')),
    );
  }
}
