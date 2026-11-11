// The structure around notes: subpages, pins, `[[links]]`, backlinks, templates
// and the flashcards that come from `Begriff :: Erklärung` lines.
// Ported from NotePages.swift and LearningStore.syncCards.

import 'dart:math';

import '../data/dates.dart';
import '../data/entities.dart';
import '../data/store.dart';
import 'markup.dart';

/// Ready-made page structures, like Notion templates, for school.
enum NoteTemplate {
  lesson('Stundenmitschrift', '## Thema\nWorum geht es heute?\n\n## Mitschrift\n-\n\n## Hausaufgabe\n- [ ] Aufgabe eintragen'),
  cornell(
    'Cornell-Notiz',
    '## Fragen\n- Was ist …?\n- Warum …?\n\n## Notizen\nHier mitschreiben.\n\n---\n## Zusammenfassung\n'
        '> In zwei, drei Sätzen: Worum ging es?',
  ),
  vocabulary(
    'Vokabeln',
    '## Vokabeln\nJede Zeile mit zwei Doppelpunkten wird automatisch eine Karteikarte.\n\nthe house :: das Haus\nto learn :: lernen',
  ),
  experiment(
    'Versuchsprotokoll',
    '## Fragestellung\nWas wollen wir herausfinden?\n\n## Vermutung\n> Ich vermute, dass …\n\n## Material\n-\n\n'
        '## Durchführung\nSchritt für Schritt.\n\n## Beobachtung\n| Zeit | Messwert |\n|---|---|\n| 0 min | |\n\n'
        '## Auswertung\nErgebnis und Erklärung.',
  ),
  summary(
    'Lernzettel',
    '## Das Wichtigste\n> Der eine Satz, den ich mir merken muss.\n\n## Begriffe\nBegriff :: Erklärung\n\n'
        '## Kann ich das?\n- [ ] Ich kann es erklären\n- [ ] Ich kann eine Aufgabe dazu lösen',
  ),
  presentation(
    'Referat',
    '## Gliederung\n1. Einleitung\n2. Hauptteil\n3. Fazit\n\n## Quellen\n-\n\n'
        '## Bis zum Vortrag\n- [ ] Recherche\n- [ ] Folien\n- [ ] Probe halten',
  );

  const NoteTemplate(this.title, this.body);
  final String title;
  final String body;
}

/// How the notes list is grouped (iPhone: "Ordnen").
enum NoteGrouping {
  recent('Zuletzt bearbeitet'),
  subject('Nach Fach'),
  folder('Nach Ordner'),
  exam('Nach Prüfung');

  const NoteGrouping(this.title);
  final String title;
}

extension NotePages on Store {
  NoteMeta? metaOf(String noteUid) {
    for (final rec in records(Kind.noteMeta)) {
      if (rec.ref('note') == noteUid) return NoteMeta(rec);
    }
    return null;
  }

  Rec ensureMeta(String noteUid) => metaOf(noteUid)?.rec ?? add(Kind.noteMeta, {'note': noteUid});

  bool isPinned(String noteUid) => metaOf(noteUid)?.pinned ?? false;

  /// Subpages, oldest first.
  List<Note> childrenOf(String noteUid) {
    final ids = {for (final m in records(Kind.noteMeta).map(NoteMeta.new)) if (m.parent == noteUid) ?m.note};
    return notes.where((n) => ids.contains(n.uid)).toList()..sort((a, b) => _created(a).compareTo(_created(b)));
  }

  Note? parentOf(String noteUid) => note(metaOf(noteUid)?.parent);

  /// Notes this note links to with `[[Titel]]`.
  List<Note> linkedFrom(Note source) {
    final all = notes;
    return [
      for (final title in Markup.links(source.body))
        ?all.where((n) => n.uid != source.uid && sameTitle(n.title, title)).firstOrNull,
    ];
  }

  /// Notes that link to this one.
  List<Note> backlinksTo(Note target) {
    if (target.title.trim().isEmpty) return const [];
    return notes
        .where((other) => other.uid != target.uid && Markup.links(other.body).any((t) => sameTitle(t, target.title)))
        .toList();
  }

  /// Titles linked with `[[…]]` that no note has yet.
  List<String> missingLinks(Note source) {
    final all = notes;
    return Markup.links(source.body).where((title) => !all.any((n) => sameTitle(n.title, title))).toList();
  }

  /// A new page inside [parentUid], with the parent's subject, topic, exam, folder and handwriting.
  Note addSubpage(String parentUid, {String title = ''}) {
    final parent = note(parentUid);
    final child = add(Kind.note, {
      'title': title,
      'seed': Random().nextInt(999999) + 1,
      if (parent != null) ...{
        for (final key in const ['subject', 'topic', 'exam', 'folder', 'profile'])
          if (parent.rec.data[key] != null) key: parent.rec.data[key],
      },
    });
    add(Kind.noteMeta, {'note': child.uid, 'parent': parentUid});
    return Note(child);
  }

  /// A new note from a template ("Aus Vorlage").
  Note addFromTemplate(NoteTemplate template, {String? subject}) {
    final rec = add(Kind.note, {
      'title': template.title,
      'body': template.body,
      'seed': Random().nextInt(999999) + 1,
      'subject': ?subject,
    });
    add(Kind.noteMeta, {'note': rec.uid, 'template': template.name});
    return Note(rec);
  }

  void togglePin(String noteUid) {
    final meta = ensureMeta(noteUid);
    update(meta, (d) => d['pinned'] = !(d['pinned'] == true));
  }

  /// Deletes a note; its subpages move up one level. Its own flashcards go too.
  void deleteNote(Note target) {
    final own = metaOf(target.uid);
    for (final rec in records(Kind.noteMeta).toList()) {
      if (rec.ref('parent') == target.uid) update(rec, (d) => d['parent'] = own?.parent);
    }
    if (own != null) delete(own.rec);
    for (final card in records(Kind.card).toList()) {
      if (card.ref('note') == target.uid) delete(card);
    }
    delete(target.rec);
  }

  /// Keeps the note's flashcards in step with its `Begriff :: Erklärung` lines:
  /// same front → back updated (learning progress kept), new lines → new cards,
  /// removed lines → cards deleted. Only the device where the note was edited does this.
  void syncCards(Note source) {
    final extracted = Markup.flashcards(source.body);
    final remaining = records(Kind.card).where((c) => c.ref('note') == source.uid).toList();
    for (final (front, back) in extracted) {
      final index = remaining.indexWhere((c) => c.str('front') == front);
      if (index >= 0) {
        final card = remaining.removeAt(index);
        if (card.str('back') != back || card.ref('subject') != source.subject || card.ref('topic') != source.topic) {
          update(card, (d) {
            d['back'] = back;
            d['subject'] = source.subject;
            d['topic'] = source.topic;
          });
        }
      } else {
        add(Kind.card, {
          'front': front,
          'back': back,
          'note': source.uid,
          'subject': ?source.subject,
          'topic': ?source.topic,
          'due': isoDate(DateTime.now()),
        });
      }
    }
    for (final stale in remaining) {
      delete(stale);
    }
  }

  /// Notes listed at the top level: not pinned (they have their own section)
  /// and not a subpage (they appear inside their parent).
  Set<String> hiddenFromList() => {
        for (final m in records(Kind.noteMeta).map(NoteMeta.new))
          if (m.pinned || m.parent != null) ?m.note,
      };

  static String _created(Note n) => n.rec.str('createdAt');
}

/// Titles match ignoring case, accents and surrounding spaces (iPhone: caseInsensitive, diacriticInsensitive).
bool sameTitle(String a, String b) => _fold(a) == _fold(b);

const _accents = {
  'a': 'äàáâãå', 'e': 'èéêë', 'i': 'ìíîï', 'o': 'öòóôõ', 'u': 'üùúû', 'n': 'ñ', 'c': 'ç', 'ss': 'ß',
};

String _fold(String text) {
  var result = text.trim().toLowerCase();
  for (final MapEntry(key: plain, value: accented) in _accents.entries) {
    for (final rune in accented.runes) {
      result = result.replaceAll(String.fromCharCode(rune), plain);
    }
  }
  return result;
}
