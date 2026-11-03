import 'package:flutter/material.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import 'widgets.dart';

Future<void> openExam(BuildContext context, Exam? exam, {String? subject}) => Navigator.push(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => ExamEditor(exam: exam, subject: subject)),
    );

/// Date, kind, room and notes of an exam (the learning plan stays on the iPhone for now).
class ExamEditor extends StatefulWidget {
  const ExamEditor({super.key, this.exam, this.subject});
  final Exam? exam;
  final String? subject;

  @override
  State<ExamEditor> createState() => _ExamEditorState();
}

class _ExamEditorState extends State<ExamEditor> {
  late final TextEditingController _title;
  late final TextEditingController _room;
  late final TextEditingController _notes;
  late final TextEditingController _duration;
  String? _subject;
  String _kind = 'classTest';
  late DateTime _date;
  bool _hasTime = false;

  @override
  void initState() {
    super.initState();
    final exam = widget.exam;
    _title = TextEditingController(text: exam?.title ?? '');
    _room = TextEditingController(text: exam?.room ?? '');
    _notes = TextEditingController(text: exam?.notes ?? '');
    _duration = TextEditingController(text: '${exam?.durationMinutes ?? 90}');
    _subject = exam?.subject ?? widget.subject;
    _kind = exam?.kind ?? 'classTest';
    _date = exam?.date ?? addDays(startOfDay(DateTime.now()), 7);
    _hasTime = exam?.hasTime ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _room.dispose();
    _notes.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _save() {
    final fields = <String, dynamic>{
      'title': _title.text.trim(),
      'kind': _kind,
      'date': isoDate(_hasTime ? _date : startOfDay(_date)),
      'hasTime': _hasTime,
      'durationMinutes': int.tryParse(_duration.text.trim()) ?? 90,
      'room': _room.text.trim(),
      'notes': _notes.text.trim(),
      'subject': _subject,
    };
    final exam = widget.exam;
    if (exam == null) {
      store.add(Kind.exam, fields);
    } else {
      store.update(exam.rec, (d) {
        d.addAll(fields);
        if (_subject == null) d.remove('subject');
      });
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final exam = widget.exam;
    if (exam == null || !await confirm(context, 'Prüfung löschen?')) return;
    store.delete(exam.rec);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.exam == null ? 'Neue Prüfung' : 'Prüfung'),
          actions: [
            if (widget.exam != null) IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete),
            TextButton(onPressed: _save, child: const Text('Fertig')),
          ],
        ),
        body: PageBody(maxWidth: 640, children: [
          const SizedBox(height: 8),
          SubjectField(value: _subject, onChanged: (v) => setState(() => _subject = v)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Art'),
            items: [for (final e in examKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _kind = v ?? 'classTest'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Titel (optional)', hintText: 'z. B. Lineare Funktionen'),
          ),
          const SectionTitle('Termin'),
          Group(children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(Fmt.longDay(_date)),
              onTap: () async {
                final day = await pickDay(context, _date);
                if (day != null) setState(() => _date = DateTime(day.year, day.month, day.day, _date.hour, _date.minute));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.schedule),
              title: Text(_hasTime ? 'Um ${Fmt.time(_date)}' : 'Uhrzeit'),
              value: _hasTime,
              onChanged: (on) async {
                if (!on) {
                  setState(() => _hasTime = false);
                  return;
                }
                final time = await pickTime(context, _date);
                if (time != null) {
                  setState(() {
                    _date = DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);
                    _hasTime = true;
                  });
                }
              },
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(controller: _room, decoration: const InputDecoration(labelText: 'Raum'))),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Dauer (Min.)'),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'Notizen, Themen', alignLabelWithHint: true),
          ),
        ]),
      );
}
