import 'package:flutter/material.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import 'home.dart';
import 'homework_import.dart';
import 'task_editor.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Filter { open, overdue, done }

/// Open, overdue and done tasks, grouped by due date and filterable by subject.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _Filter _filter = _Filter.open;
  String? _subject;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Aufgaben'),
          actions: [
            IconButton(
              tooltip: 'Hausaufgabe fotografieren',
              icon: const Icon(Icons.document_scanner_outlined),
              onPressed: () => importHomework(context),
            ),
            ...shellActions(context),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Neue Aufgabe',
          onPressed: () => openTaskEditor(context, subject: _subject),
          child: const Icon(Icons.add),
        ),
        body: StoreBuilder(builder: (context, store) {
          final now = DateTime.now();
          var tasks = store.tasks.where((t) => _subject == null || t.subject == _subject).toList();
          tasks = switch (_filter) {
            _Filter.open => tasks.where((t) => !t.isDone).toList(),
            _Filter.overdue => tasks.where((t) => t.isOverdue(now)).toList(),
            _Filter.done => tasks.where((t) => t.isDone).toList()
              ..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt)),
          };
          final groups = _filter == _Filter.done ? {'Erledigt': tasks} : _group(tasks, now);

          return PageBody(children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(switch (f) { _Filter.open => 'Offen', _Filter.overdue => 'Überfällig', _Filter.done => 'Erledigt' }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                if (store.subjects.isNotEmpty)
                  PopupMenuButton<String?>(
                    tooltip: 'Fach',
                    onSelected: (uid) => setState(() => _subject = uid == '' ? null : uid),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: '', child: Text('Alle Fächer')),
                      for (final s in store.subjects) PopupMenuItem(value: s.uid, child: Text(s.name)),
                    ],
                    child: Chip(
                      avatar: _subject == null ? const Icon(Icons.filter_list, size: 18) : SubjectDot(store.subject(_subject)?.colorKey),
                      label: Text(store.subject(_subject)?.name ?? 'Alle Fächer'),
                    ),
                  ),
              ],
            ),
            if (tasks.isEmpty)
              EmptyState(
                icon: Icons.check_circle_outline,
                title: _filter == _Filter.done ? 'Noch nichts erledigt' : 'Alles erledigt',
                message: _filter == _Filter.open
                    ? 'Neue Aufgaben mit +, oder fotografiere die Hausaufgabe von der Tafel.'
                    : 'Hier ist gerade nichts.',
              ),
            for (final entry in groups.entries)
              if (entry.value.isNotEmpty) ...[
                SectionTitle(entry.key),
                Group(children: [for (final task in entry.value) TaskTile(task)]),
              ],
          ]);
        }),
      );

  static Map<String, List<Task>> _group(List<Task> tasks, DateTime now) {
    final today = startOfDay(now);
    final groups = <String, List<Task>>{
      'Überfällig': [],
      'Heute': [],
      'Morgen': [],
      'Diese Woche': [],
      'Später': [],
      'Ohne Datum': [],
    };
    for (final task in tasks) {
      final due = task.dueDate;
      if (due == null) {
        groups['Ohne Datum']!.add(task);
      } else if (task.isOverdue(now)) {
        groups['Überfällig']!.add(task);
      } else {
        final days = daysBetween(today, due);
        final weekEnd = daysBetween(today, addDays(startOfWeek(today), 6));
        groups[days <= 0 ? 'Heute' : days == 1 ? 'Morgen' : days <= weekEnd ? 'Diese Woche' : 'Später']!.add(task);
      }
    }
    for (final list in groups.values) {
      list.sort((a, b) {
        final da = a.deadline, db = b.deadline;
        if (da == null || db == null) return b.createdAt.compareTo(a.createdAt);
        final byDate = da.compareTo(db);
        return byDate != 0 ? byDate : b.priority.compareTo(a.priority);
      });
    }
    return groups;
  }
}

/// One task with a tick box. Tap opens the editor.
class TaskTile extends StatelessWidget {
  const TaskTile(this.task, {super.key, this.showSubject = true});
  final Task task;
  final bool showSubject;

  @override
  Widget build(BuildContext context) {
    final subject = store.subject(task.subject);
    final subtasks = store.subtasksOf(task.uid);
    final overdue = task.isOverdue();
    final parts = [
      if (showSubject && subject != null) subject.name,
      if (task.dueDate != null) dueLabel(task),
      if (subtasks.isNotEmpty) '${subtasks.where((s) => s.isDone).length}/${subtasks.length}',
    ];
    return ListTile(
      leading: Checkbox(
        value: task.isDone,
        onChanged: (done) => setDone(task, done == true),
      ),
      title: Text(
        task.title.isEmpty ? taskKinds[task.kind]! : task.title,
        style: TextStyle(
          decoration: task.isDone ? TextDecoration.lineThrough : null,
          color: task.isDone ? context.colors.secondaryInk : null,
        ),
      ),
      subtitle: parts.isEmpty
          ? null
          : Text(parts.join(' · '), style: TextStyle(color: overdue ? context.colors.marginRed : context.colors.secondaryInk)),
      trailing: task.priority == 2 ? Icon(Icons.priority_high, color: context.colors.marginRed, size: 18) : null,
      onTap: () => openTaskEditor(context, task: task),
    );
  }
}

void setDone(Task task, bool done) {
  store.update(task.rec, (d) {
    d['status'] = done ? 'done' : 'open';
    if (done) {
      d['completedAt'] ??= isoDate(DateTime.now());
    } else {
      d.remove('completedAt');
    }
  });
}
