// Connects stored notes and handwriting profiles to the layout engine.
// Ported from NoteRendering.swift.

import 'dart:typed_data';

import '../data/dates.dart';
import '../data/entities.dart';
import '../data/store.dart';
import 'handwriting_library.dart';
import 'note_layout.dart';
import 'pdf_export.dart';

abstract final class NoteRendering {
  /// "Mathematik · 02.11.2026"
  static String header(Note note, Store store) {
    final subject = store.subject(note.subject)?.name;
    return [?subject, Fmt.numeric(note.noteDate)].join(' · ');
  }

  static NoteContent content(Note note, Store store, {String? title, String? body}) => NoteContent(
        title: title ?? note.title,
        header: header(note, store),
        body: body ?? note.body,
        seed: note.rec.integer('seed', 1),
      );

  static List<LaidOutPage> layout(Note note, Store store, HandwritingLibrary library, {String? title, String? body}) {
    final settings = PageSettings.fromNote(note.rec.data);
    final profile = library.profileFor(note.rec.ref('profile'));
    final font = library.font(profile?.uid, settings.penRatio);
    return NoteLayout.layout(content(note, store, title: title, body: body), settings, font);
  }

  static Future<Uint8List> pdf(Note note, Store store, HandwritingLibrary library) {
    final pages = layout(note, store, library);
    return NotePdf.build(pages, PageSettings.fromNote(note.rec.data), title: note.title.trim().isEmpty ? 'Notiz' : note.title.trim());
  }

  /// A file name without characters Windows doesn't allow.
  static String fileName(Note note) {
    final safe = note.title.split(RegExp(r'[/\\:?*"<>|]')).join('-').trim();
    return '${safe.isEmpty ? 'Notiz' : safe}.pdf';
  }
}
