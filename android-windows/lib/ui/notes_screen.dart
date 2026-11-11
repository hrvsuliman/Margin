import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import '../handwriting/note_rendering.dart';
import '../logic/note_pages.dart';
import 'handwriting_screen.dart';
import 'home.dart';
import 'note_editor.dart';
import 'theme.dart';
import 'widgets.dart';

/// All notes: pinned ones first, then grouped as chosen. Subpages appear inside
/// their parent. Opening one shows it in your handwriting.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  NoteGrouping get _grouping =>
      NoteGrouping.values.firstWhere((g) => g.name == store.settings['notesGrouping'], orElse: () => NoteGrouping.recent);

  List<(String, List<Note>)> _groups(List<Note> list) {
    switch (_grouping) {
      case NoteGrouping.recent:
        return [('Zuletzt bearbeitet', list)];
      case NoteGrouping.subject:
        final known = {for (final s in store.subjects) s.uid};
        return [
          for (final subject in store.subjects)
            if (list.where((n) => n.subject == subject.uid).toList() case final matches when matches.isNotEmpty)
              (subject.name, matches),
          if (list.where((n) => !known.contains(n.subject)).toList() case final other when other.isNotEmpty)
            ('Ohne Fach', other),
        ];
      case NoteGrouping.folder:
        final names = {for (final n in list) n.folder}.toList()
          ..sort((a, b) => a.isEmpty != b.isEmpty ? (a.isEmpty ? 1 : -1) : a.toLowerCase().compareTo(b.toLowerCase()));
        return [
          for (final name in names) (name.isEmpty ? 'Ohne Ordner' : name, list.where((n) => n.folder == name).toList()),
        ];
      case NoteGrouping.exam:
        final known = {for (final e in store.exams) e.uid};
        return [
          for (final exam in store.exams)
            if (list.where((n) => n.exam == exam.uid).toList() case final matches when matches.isNotEmpty)
              ('${store.examTitle(exam)} · ${Fmt.dayMonth(exam.date)}', matches),
          if (list.where((n) => !known.contains(n.exam)).toList() case final other when other.isNotEmpty)
            ('Ohne Prüfung', other),
        ];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notizen'),
          actions: [
            PopupMenuButton<NoteGrouping>(
              tooltip: 'Ordnen',
              icon: const Icon(Icons.filter_list),
              initialValue: _grouping,
              onSelected: (g) => store.setSetting('notesGrouping', g.name),
              itemBuilder: (_) => [
                for (final g in NoteGrouping.values) CheckedPopupMenuItem(value: g, checked: g == _grouping, child: Text(g.title)),
              ],
            ),
            PopupMenuButton<NoteTemplate>(
              tooltip: 'Aus Vorlage',
              icon: const Icon(Icons.note_add_outlined),
              onSelected: (t) => openNote(context, store.addFromTemplate(t).uid),
              itemBuilder: (_) => [
                for (final t in NoteTemplate.values) PopupMenuItem(value: t, child: Text(t.title)),
              ],
            ),
            IconButton(
              tooltip: 'Handschrift',
              icon: const Icon(Icons.draw_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HandwritingScreen())),
            ),
            ...shellActions(context),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Neue Notiz',
          onPressed: () => openNewNote(context),
          child: const Icon(Icons.add),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([Services.store, Services.handwriting, _search]),
          builder: (context, _) {
            final query = _search.text.trim().toLowerCase();
            final searching = query.isNotEmpty;
            final all = store.notes;
            final matching = all
                .where((n) => !searching || n.title.toLowerCase().contains(query) || n.body.toLowerCase().contains(query))
                .toList();
            final pinned = searching ? <Note>[] : all.where((n) => store.isPinned(n.uid)).toList();
            // Subpages appear inside their parent; pinned notes in their own section (except while searching).
            final hidden = searching ? <String>{} : store.hiddenFromList();
            final rest = matching.where((n) => !hidden.contains(n.uid)).toList();
            final hasHandwriting = Services.handwriting.profiles.isNotEmpty;

            return PageBody(children: [
              if (!hasHandwriting) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.draw_outlined, color: context.colors.marginRed),
                    title: const Text('Handschrift einrichten', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Damit Notizen in deiner eigenen Schrift erscheinen – mit dem Stift oder vom iPhone.'),
                    trailing: Icon(Icons.chevron_right, color: context.colors.faintInk),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HandwritingScreen())),
                  ),
                ),
              ],
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Suchen',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(tooltip: 'Löschen', icon: const Icon(Icons.close), onPressed: _search.clear),
                    ),
                  ),
                ),
              if (all.isEmpty)
                EmptyState(
                  icon: Icons.edit_note,
                  title: 'Noch keine Notizen',
                  message: 'Schreib eine Notiz – Margin setzt sie in deine Handschrift.',
                  action: 'Neue Notiz',
                  onAction: () => openNewNote(context),
                )
              else if (matching.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Keine Treffer für „${_search.text.trim()}“.',
                      textAlign: TextAlign.center, style: TextStyle(color: context.colors.secondaryInk)),
                ),
              if (pinned.isNotEmpty) ...[
                const SectionTitle('Angeheftet'),
                Group(children: [for (final note in pinned) _NoteRow(note: note)]),
              ],
              for (final (title, notes) in _groups(rest)) ...[
                SectionTitle(title),
                Group(children: [for (final note in notes) _NoteRow(note: note)]),
              ],
            ]);
          },
        ),
      );
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final subject = store.subject(note.subject);
    final subpages = store.childrenOf(note.uid).length;
    final pinned = store.isPinned(note.uid);
    final firstLine = note.body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('[[Bild:'), orElse: () => '');
    return ListTile(
      leading: subject == null ? Icon(Icons.description_outlined, color: context.colors.faintInk) : SubjectDot(subject.colorKey, size: 14),
      title: Text(note.displayTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          [
            if (subject != null) subject.name,
            Fmt.numeric(note.noteDate),
            if (subpages > 0) subpages == 1 ? '1 Unterseite' : '$subpages Unterseiten',
          ].join(' · '),
          if (firstLine.isNotEmpty) firstLine,
        ].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: firstLine.isNotEmpty,
      onTap: () => openNote(context, note.uid),
      onLongPress: () => store.togglePin(note.uid),
      trailing: PopupMenuButton<String>(
        tooltip: 'Mehr',
        onSelected: (action) => _act(context, action),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'pin', child: Text(pinned ? 'Lösen' : 'Anheften')),
          const PopupMenuItem(value: 'subpage', child: Text('Unterseite hinzufügen')),
          const PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
          const PopupMenuItem(value: 'duplicate', child: Text('Duplizieren')),
          const PopupMenuItem(value: 'pdf', child: Text('Als PDF sichern')),
          const PopupMenuItem(value: 'delete', child: Text('Löschen')),
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, String action) async {
    switch (action) {
      case 'pin':
        store.togglePin(note.uid);
      case 'subpage':
        openNote(context, store.addSubpage(note.uid).uid);
      case 'rename':
        final title = await askText(context, 'Umbenennen', initial: note.title, action: 'Sichern');
        if (title != null) {
          store.update(note.rec, (d) {
            d['title'] = title.trim();
            d['updatedAt'] = isoDate(DateTime.now());
          });
        }
      case 'duplicate':
        final copy = store.add(Kind.note, {
          ...note.rec.data,
          'uid': null,
          'title': note.title.isEmpty ? 'Kopie' : '${note.title} (Kopie)',
          'createdAt': isoDate(DateTime.now()),
          'updatedAt': isoDate(DateTime.now()),
        });
        if (context.mounted) openNote(context, copy.uid);
      case 'pdf':
        await exportNotePdf(context, note);
      case 'delete':
        final ok = await confirm(context, '„${note.displayTitle}“ löschen?',
            message: 'Die Notiz wird auf allen Geräten gelöscht. Unterseiten bleiben erhalten.');
        if (ok) store.deleteNote(note);
    }
  }
}

void openNote(BuildContext context, String uid) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(noteUid: uid)));

/// A new, empty note with its own variation seed (1 … 999 999, as on the iPhone).
void openNewNote(BuildContext context, {String? subject}) {
  final note = store.add(Kind.note, {
    'seed': Random().nextInt(999999) + 1,
    'subject': ?subject,
  });
  openNote(context, note.uid);
}

/// Renders the note and saves it as a PDF where the user chooses (Windows) or
/// in Margin's folder (Android), then offers to open it.
Future<void> exportNotePdf(BuildContext context, Note note) async {
  final messenger = ScaffoldMessenger.of(context);
  final bytes = await NoteRendering.pdf(note, store, Services.handwriting);
  final name = NoteRendering.fileName(note);
  String path;
  if (Platform.isAndroid) {
    final folder = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    path = '${folder.path}${Platform.pathSeparator}$name';
  } else {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf'])],
    );
    if (location == null) return;
    path = location.path.toLowerCase().endsWith('.pdf') ? location.path : '${location.path}.pdf';
  }
  await File(path).writeAsBytes(bytes, flush: true);
  messenger.showSnackBar(SnackBar(
    content: Text('PDF gesichert: $path'),
    action: Platform.isAndroid ? null : SnackBarAction(label: 'Öffnen', onPressed: () => launchUrl(Uri.file(path))),
  ));
}
