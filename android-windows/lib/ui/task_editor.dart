import 'package:flutter/material.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import '../data/store.dart';
import '../logic/homework_parser.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openTaskEditor(BuildContext context, {Task? task, String? subject, HomeworkSuggestion? suggestion}) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TaskEditor(task: task, subject: subject, suggestion: suggestion),
      ),
    );

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, this.task, this.subject, this.suggestion});
  final Task? task;
  final String? subject;
  final HomeworkSuggestion? suggestion;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _SubtaskDraft {
  _SubtaskDraft(this.uid, this.title, this.isDone);
  final String? uid;
  String title;
  bool isDone;
}

class _TaskEditorState extends State<TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _details;
  late final TextEditingController _minutes;
  late final TextEditingController _newSubtask;
  String? _subject;
  String _kind = 'homework';
  int _priority = 1;
  String _status = 'open';
  DateTime? _due;
  bool _hasTime = false;
  final List<_SubtaskDraft> _subtasks = [];

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final suggestion = widget.suggestion;
    _title = TextEditingController(text: task?.title ?? suggestion?.title ?? '');
    _details = TextEditingController(text: task?.details ?? suggestion?.details ?? '');
    _minutes = TextEditingController(text: task == null || task.estimatedMinutes == 0 ? '' : '${task.estimatedMinutes}');
    _newSubtask = TextEditingController();
    _subject = task?.subject ?? widget.subject;
    if (suggestion?.subjectName != null) {
      _subject = store.subjects.where((s) => s.name == suggestion!.subjectName).firstOrNull?.uid ?? _subject;
    }
    if (task != null) {
      _kind = task.kind;
      _priority = task.priority;
      _status = task.status;
      _due = task.dueDate;
      _hasTime = task.hasDueTime;
      for (final s in store.subtasksOf(task.uid)) {
        _subtasks.add(_SubtaskDraft(s.uid, s.title, s.isDone));
      }
    } else {
      _due = suggestion?.dueDate;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _minutes.dispose();
    _newSubtask.dispose();
    super.dispose();
  }

  void _save() {
    final due = _due;
    final fields = <String, dynamic>{
      'title': _title.text.trim(),
      'details': _details.text.trim(),
      'kind': _kind,
      'priority': _priority,
      'status': _status,
      'hasDueTime': due != null && _hasTime,
      'estimatedMinutes': int.tryParse(_minutes.text.trim()) ?? 0,
      'subject': _subject,
      'dueDate': due == null ? null : isoDate(_hasTime ? due : startOfDay(due)),
    };
    Rec rec;
    final existing = widget.task;
    if (existing == null) {
      rec = store.add(Kind.task, fields);
      if (_status == 'done') store.update(rec, (d) => d['completedAt'] = isoDate(DateTime.now()));
    } else {
      rec = existing.rec;
      store.update(rec, (d) {
        final wasDone = d['status'] == 'done';
        d.addAll(fields);
        if (_status == 'done' && !wasDone) d['completedAt'] = isoDate(DateTime.now());
        if (_status != 'done') d.remove('completedAt');
        for (final key in ['subject', 'dueDate']) {
          if (d[key] == null) d.remove(key);
        }
      });
    }
    _saveSubtasks(rec.uid);
    Navigator.pop(context);
  }

  void _saveSubtasks(String taskUid) {
    final keep = <String>{};
    for (final (index, draft) in _subtasks.indexed) {
      final rec = store.byUid(draft.uid);
      if (rec == null) {
        keep.add(store.add(Kind.subtask, {'title': draft.title, 'isDone': draft.isDone, 'sortIndex': index, 'task': taskUid}).uid);
      } else {
        keep.add(rec.uid);
        if (rec.str('title') != draft.title || rec.flag('isDone') != draft.isDone || rec.integer('sortIndex') != index) {
          store.update(rec, (d) {
            d['title'] = draft.title;
            d['isDone'] = draft.isDone;
            d['sortIndex'] = index;
          });
        }
      }
    }
    for (final old in store.subtasksOf(taskUid)) {
      if (!keep.contains(old.uid)) store.delete(old.rec);
    }
  }

  Future<void> _delete() async {
    final task = widget.task;
    if (task == null) return;
    if (!await confirm(context, 'Aufgabe löschen?')) return;
    for (final s in store.subtasksOf(task.uid)) {
      store.delete(s.rec);
    }
    store.delete(task.rec);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDue() async {
    final day = await pickDay(context, _due);
    if (day == null) return;
    final old = _due;
    setState(() => _due = DateTime(day.year, day.month, day.day, old?.hour ?? 8, old?.minute ?? 0));
  }

  Future<void> _pickTime() async {
    final time = await pickTime(context, _due);
    if (time == null) return;
    final day = _due ?? DateTime.now();
    setState(() {
      _due = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _hasTime = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Neue Aufgabe' : 'Aufgabe'),
        actions: [
          if (widget.task != null)
            IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _save, child: const Text('Fertig')),
        ],
      ),
      body: PageBody(maxWidth: 640, children: [
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          autofocus: widget.task == null && widget.suggestion == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Was ist zu tun?', hintText: 'S. 42 Nr. 3'),
        ),
        const SizedBox(height: 14),
        SubjectField(value: _subject, onChanged: (v) => setState(() => _subject = v)),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Art'),
          items: [for (final e in taskKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _kind = v ?? 'homework'),
        ),
        const SectionTitle('Fällig'),
        Group(children: [
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(due == null ? 'Kein Datum' : Fmt.longDay(due)),
            trailing: due == null ? null : IconButton(
              tooltip: 'Datum entfernen',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _due = null;
                _hasTime = false;
              }),
            ),
            onTap: _pickDue,
          ),
          if (due != null)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(_hasTime ? 'Um ${Fmt.time(due)}' : 'Ganzer Tag'),
              trailing: _hasTime
                  ? IconButton(
                      tooltip: 'Uhrzeit entfernen',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _hasTime = false),
                    )
                  : null,
              onTap: _pickTime,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(spacing: 8, children: [
              for (final (label, days) in [('Heute', 0), ('Morgen', 1), ('Nächste Woche', 7)])
                ActionChip(
                  label: Text(label),
                  onPressed: () => setState(() => _due = addDays(startOfDay(DateTime.now()), days)),
                ),
            ]),
          ),
        ]),
        const SectionTitle('Details'),
        SegmentedButton<int>(
          segments: [for (final e in taskPriorities.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {_priority},
          onSelectionChanged: (s) => setState(() => _priority = s.first),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [for (final e in taskStatuses.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _status = v ?? 'open'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _minutes,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Geschätzte Minuten'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _details,
          minLines: 3,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Notizen', alignLabelWithHint: true),
        ),
        const SectionTitle('Teilschritte'),
        Group(children: [
          for (final draft in _subtasks)
            ListTile(
              leading: Checkbox(value: draft.isDone, onChanged: (v) => setState(() => draft.isDone = v == true)),
              title: Text(draft.title, style: TextStyle(decoration: draft.isDone ? TextDecoration.lineThrough : null)),
              trailing: IconButton(
                tooltip: 'Entfernen',
                icon: Icon(Icons.close, color: context.colors.secondaryInk),
                onPressed: () => setState(() => _subtasks.remove(draft)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: TextField(
              controller: _newSubtask,
              decoration: const InputDecoration(
                hintText: 'Teilschritt hinzufügen',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
              ),
              onSubmitted: (value) {
                if (value.trim().isEmpty) return;
                setState(() => _subtasks.add(_SubtaskDraft(null, value.trim(), false)));
                _newSubtask.clear();
              },
            ),
          ),
        ]),
      ]),
    );
  }
}
