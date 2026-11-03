import 'package:flutter/material.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import '../logic/learning.dart';
import 'exam_editor.dart';
import 'pinboard.dart';
import 'subjects_screen.dart';
import 'task_editor.dart';
import 'tasks_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Everything about one subject: progress to the next exam, pinboard, lessons, exams and tasks.
class SubjectPage extends StatelessWidget {
  const SubjectPage({super.key, required this.subjectUid});
  final String subjectUid;

  @override
  Widget build(BuildContext context) => StoreBuilder(builder: (context, store) {
        final subject = store.subject(subjectUid);
        if (subject == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline, title: 'Fach gelöscht', message: ''));
        }
        final today = startOfDay(DateTime.now());
        final lessons = store.lessons.where((l) => l.subject == subject.uid).toList();
        final exams = store.exams.where((e) => e.subject == subject.uid && !e.date.isBefore(today)).toList();
        final tasks = store.tasks.where((t) => t.subject == subject.uid && !t.isDone).toList()
          ..sort((a, b) => (a.deadline ?? DateTime(9999)).compareTo(b.deadline ?? DateTime(9999)));

        return Scaffold(
          appBar: AppBar(
            title: Row(children: [
              SubjectDot(subject.colorKey, size: 14),
              const SizedBox(width: 10),
              Flexible(child: Text(subject.name, overflow: TextOverflow.ellipsis)),
            ]),
            actions: [
              PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'edit') editSubject(context, subject);
                  if (action == 'delete' &&
                      await confirm(context, '${subject.name} löschen?',
                          message: 'Stunden und Pinnwand des Fachs werden gelöscht. Aufgaben, Prüfungen und Notizen bleiben (ohne Fach).')) {
                    _deleteSubject(subject);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Neue Aufgabe',
            onPressed: () => openTaskEditor(context, subject: subject.uid),
            child: const Icon(Icons.add_task),
          ),
          body: PageBody(maxWidth: 900, children: [
            if (subject.teacher.isNotEmpty || subject.room.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  [subject.teacher, subject.room].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: context.colors.secondaryInk),
                ),
              ),
            const SectionTitle('Bis zur Arbeit'),
            ExamProgressCard(subject: subject, exam: exams.firstOrNull),
            const SectionTitle('Pinnwand'),
            Pinboard(subject: subject),
            if (tasks.isNotEmpty) ...[
              SectionTitle('Aufgaben', trailing: Text('${tasks.length} offen', style: TextStyle(color: context.colors.secondaryInk))),
              Group(children: [for (final t in tasks) TaskTile(t, showSubject: false)]),
            ],
            if (lessons.isNotEmpty) ...[
              const SectionTitle('Stundenplan'),
              Group(children: [
                for (final l in lessons)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text('${weekdayNames[l.weekday - 1]}, ${Fmt.clock(l.startMinute)}–${Fmt.clock(l.endMinute)}'),
                    subtitle: l.room.isEmpty ? null : Text(l.room),
                  ),
              ]),
            ],
            if (exams.length > 1) ...[
              const SectionTitle('Weitere Prüfungen'),
              Group(children: [
                for (final e in exams.skip(1))
                  ListTile(
                    title: Text(store.examTitle(e)),
                    subtitle: Text(Fmt.longDay(e.date)),
                    onTap: () => openExam(context, e),
                  ),
              ]),
            ],
          ]),
        );
      });

  static void _deleteSubject(Subject subject) {
    for (final l in store.lessons.where((l) => l.subject == subject.uid).toList()) {
      store.delete(l.rec);
    }
    for (final p in store.pinsOf(subject.uid)) {
      store.delete(p.rec);
    }
    for (final t in store.topicsOf(subject.uid)) {
      store.delete(t.rec);
    }
    store.delete(subject.rec);
  }
}

/// Countdown, readiness, topics that sit, sessions done and minutes learned this week.
class ExamProgressCard extends StatelessWidget {
  const ExamProgressCard({super.key, required this.subject, required this.exam});
  final Subject subject;
  final Exam? exam;

  @override
  Widget build(BuildContext context) {
    final exam = this.exam;
    final now = DateTime.now();
    final weekStart = startOfWeek(now);
    final minutes = store.sessions
        .where((s) => s.subject == subject.uid && s.status == 'done')
        .where((s) => !(s.completedAt ?? s.date).isBefore(weekStart))
        .fold<int>(0, (sum, s) => sum + (s.actualMinutes > 0 ? s.actualMinutes : 0));

    if (exam == null) {
      return Group(children: [
        ListTile(
          leading: const Icon(Icons.event_available_outlined),
          title: const Text('Nächste Arbeit eintragen'),
          subtitle: minutes > 0 ? Text('Diese Woche $minutes Min. für ${subject.name} gelernt') : null,
          onTap: () => openExam(context, null, subject: subject.uid),
        ),
      ]);
    }

    final (overall, topics) = readinessFor(exam, now);
    final sitting = topics.where((t) => t.score >= 0.7).length;
    final sessions = store.sessions.where((s) => s.exam == exam.uid).toList();
    final done = sessions.where((s) => s.status == 'done').length;
    final next = sessions.where((s) => s.status == 'planned' && s.date.isAfter(now)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final days = daysBetween(now, exam.date);
    final secondary = TextStyle(color: context.colors.secondaryInk, fontSize: 13);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openExam(context, exam),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            ReadinessRing(value: overall),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(store.examTitle(exam), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  days == 0 ? 'Heute' : days == 1 ? 'Morgen' : 'In $days Tagen · ${Fmt.dayMonth(exam.date)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: days <= 3 ? context.colors.marginRed : context.colors.secondaryInk,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 12, children: [
                  if (topics.isNotEmpty) Text('$sitting/${topics.length} Themen sitzen', style: secondary),
                  if (sessions.isNotEmpty) Text('$done/${sessions.length} Einheiten', style: secondary),
                  if (topics.isEmpty) Text('Lernplan und Themen kommen vom iPhone', style: secondary),
                ]),
                if (next.isNotEmpty)
                  Text('Nächste Lerneinheit: ${Fmt.relativeDay(next.first.date)}', style: secondary.copyWith(color: context.colors.faintInk)),
                if (minutes > 0) Text('Diese Woche $minutes Min. gelernt', style: secondary),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Readiness of an exam from its learning plan (as LearningStore.readiness on the iPhone).
(double, List<TopicReadiness>) readinessFor(Exam exam, DateTime now) {
  final plan = store.records(Kind.plan).map(ExamPlan.new).where((p) => p.exam == exam.uid).firstOrNull;
  if (plan == null) return (0.0, const <TopicReadiness>[]);
  final progress = {for (final p in store.records(Kind.progress).map(TopicProgress.new)) p.topic: p};
  final results = store.records(Kind.result).map(PracticeResult.new).toList()..sort((a, b) => b.date.compareTo(a.date));
  final inputs = [
    for (final topicUid in plan.topics)
      if (store.byUid(topicUid) != null)
        ReadinessInput(
          id: topicUid,
          importance: progress[topicUid]?.importance ?? 1,
          understanding: progress[topicUid]?.understanding ?? 0,
          completion: progress[topicUid]?.completion ?? 0,
          lastStudied: progress[topicUid]?.lastStudied,
          scores: [for (final r in results) if (r.topic == topicUid) r.score],
        ),
  ];
  return Readiness.evaluate(inputs, now);
}
