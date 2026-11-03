import 'package:flutter/material.dart';

import '../data/entities.dart';
import 'home.dart';
import 'subject_page.dart';
import 'theme.dart';
import 'widgets.dart';

class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fächer'), actions: shellActions(context)),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Neues Fach',
          onPressed: () => editSubject(context, null),
          child: const Icon(Icons.add),
        ),
        body: StoreBuilder(builder: (context, store) {
          final subjects = store.subjects;
          if (subjects.isEmpty) {
            return EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Noch keine Fächer',
              message: 'Lege deine Fächer an – oder schalte den Abgleich ein, dann kommen sie vom iPhone.',
              action: 'Fach anlegen',
              onAction: () => editSubject(context, null),
            );
          }
          final now = DateTime.now();
          return PageBody(children: [
            const SizedBox(height: 8),
            Group(children: [
              for (final subject in subjects)
                ListTile(
                  leading: SubjectDot(subject.colorKey, size: 14),
                  title: Text(subject.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_summary(subject, now)),
                  trailing: Icon(Icons.chevron_right, color: context.colors.faintInk),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectPage(subjectUid: subject.uid))),
                ),
            ]),
          ]);
        }),
      );

  static String _summary(Subject subject, DateTime now) {
    final open = store.tasks.where((t) => t.subject == subject.uid && !t.isDone).length;
    final pins = store.pinsOf(subject.uid).length;
    return [
      if (subject.teacher.isNotEmpty) subject.teacher,
      open == 1 ? '1 Aufgabe offen' : '$open Aufgaben offen',
      if (pins > 0) '$pins angeheftet',
    ].join(' · ');
  }
}

/// Name, colour, teacher and room of a subject.
Future<void> editSubject(BuildContext context, Subject? subject) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SubjectEditor(subject: subject),
    );

class _SubjectEditor extends StatefulWidget {
  const _SubjectEditor({this.subject});
  final Subject? subject;

  @override
  State<_SubjectEditor> createState() => _SubjectEditorState();
}

class _SubjectEditorState extends State<_SubjectEditor> {
  late final _name = TextEditingController(text: widget.subject?.name ?? '');
  late final _teacher = TextEditingController(text: widget.subject?.teacher ?? '');
  late final _room = TextEditingController(text: widget.subject?.room ?? '');
  late String _color = widget.subject?.colorKey ?? _nextColor();

  static String _nextColor() {
    final used = store.subjects.map((s) => s.colorKey).toSet();
    return subjectColors.keys.firstWhere((k) => !used.contains(k), orElse: () => 'blue');
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final fields = {'name': name, 'colorKey': _color, 'teacher': _teacher.text.trim(), 'room': _room.text.trim()};
    final subject = widget.subject;
    if (subject == null) {
      store.add(Kind.subject, {...fields, 'sortIndex': store.subjects.length});
    } else {
      store.update(subject.rec, (d) => d.addAll(fields));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.subject == null ? 'Neues Fach' : 'Fach bearbeiten', style: context.serifTitle),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.subject == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Mathematik'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _teacher, decoration: const InputDecoration(labelText: 'Lehrkraft'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _room, decoration: const InputDecoration(labelText: 'Raum'))),
            ]),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in subjectColors.entries)
                  Tooltip(
                    message: entry.value.$1,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = entry.key),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: subjectColor(context, entry.key),
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == entry.key ? context.colors.ink : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Sichern')),
          ],
        ),
      );
}
