import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import '../handwriting/note_rendering.dart';
import 'handwriting_screen.dart';
import 'home.dart';
import 'note_editor.dart';
import 'theme.dart';
import 'widgets.dart';

/// All notes, newest change first. Opening one shows it in your handwriting.
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notizen'),
          actions: [
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
            final notes = store.notes
                .where((n) => query.isEmpty || n.title.toLowerCase().contains(query) || n.body.toLowerCase().contains(query))
                .toList();
            final pinned = {for (final m in store.records(Kind.noteMeta).map(NoteMeta.new)) if (m.pinned && m.note != null) m.note!};
            final top = notes.where((n) => pinned.contains(n.uid)).toList();
            final rest = notes.where((n) => !pinned.contains(n.uid)).toList();
            final hasHandwriting = Services.handwriting.profiles.isNotEmpty;

            return PageBody(children: [
              if (!hasHandwriting) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.draw_outlined, color: context.colors.marginRed),
                    title: const Text('Handschrift einrichten', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Damit Notizen in deiner eigenen Schrift erscheinen.'),
                    trailing: Icon(Icons.chevron_right, color: context.colors.faintInk),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HandwritingScreen())),
                  ),
                ),
              ],
              if (store.notes.isNotEmpty)
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
              if (store.notes.isEmpty)
                EmptyState(
                  icon: Icons.edit_note,
                  title: 'Noch keine Notizen',
                  message: 'Schreib eine Notiz – Margin setzt sie in deine Handschrift.',
                  action: 'Neue Notiz',
                  onAction: () => openNewNote(context),
                )
              else if (notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Keine Treffer für „${_search.text.trim()}“.',
                      textAlign: TextAlign.center, style: TextStyle(color: context.colors.secondaryInk)),
                ),
              if (top.isNotEmpty) ...[
                const SectionTitle('Angeheftet'),
                Group(children: [for (final note in top) _NoteRow(note: note)]),
              ],
              if (rest.isNotEmpty) ...[
                if (top.isNotEmpty) const SectionTitle('Notizen') else const SizedBox(height: 12),
                Group(children: [for (final note in rest) _NoteRow(note: note)]),
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
    final firstLine = note.body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('[[Bild:'), orElse: () => '');
    return ListTile(
      leading: subject == null ? Icon(Icons.description_outlined, color: context.colors.faintInk) : SubjectDot(subject.colorKey, size: 14),
      title: Text(note.displayTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          [if (subject != null) subject.name, Fmt.numeric(note.noteDate)].join(' · '),
          if (firstLine.isNotEmpty) firstLine,
        ].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: firstLine.isNotEmpty,
      onTap: () => openNote(context, note.uid),
      trailing: PopupMenuButton<String>(
        tooltip: 'Mehr',
        onSelected: (action) => _act(context, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
          PopupMenuItem(value: 'duplicate', child: Text('Duplizieren')),
          PopupMenuItem(value: 'pdf', child: Text('Als PDF sichern')),
          PopupMenuItem(value: 'delete', child: Text('Löschen')),
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, String action) async {
    switch (action) {
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
            message: 'Die Notiz wird auf allen Geräten gelöscht.');
        if (ok) store.delete(note.rec);
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
