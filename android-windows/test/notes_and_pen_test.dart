import 'package:flutter_test/flutter_test.dart';
import 'package:margin/data/entities.dart';
import 'package:margin/data/store.dart';
import 'package:margin/handwriting/analysis.dart';
import 'package:margin/handwriting/capture.dart';
import 'package:margin/handwriting/geometry.dart';
import 'package:margin/handwriting/handwriting_font.dart';
import 'package:margin/handwriting/handwriting_library.dart';
import 'package:margin/handwriting/note_layout.dart';
import 'package:margin/logic/markup_editing.dart';
import 'package:margin/logic/note_pages.dart';

/// A pen stroke from (x0, y0) to (x1, y1) in canvas points, [n] samples, [seconds] long.
List<CapturedPoint> line(double x0, double y0, double x1, double y1,
    {int n = 20, double seconds = 0.4, double? pressure}) => [
      for (var i = 0; i < n; i++)
        CapturedPoint(x0 + (x1 - x0) * i / (n - 1), y0 + (y1 - y0) * i / (n - 1), seconds * i / (n - 1), pressure),
    ];

void main() {
  group('pen capture (GlyphProcessing)', () {
    const guide = CaptureGuide(200, 200); // x-height 40, baseline at 132

    test('baseline is y = 0, x-height line y = −1, ink starts at x = 0', () {
      final strokes = GlyphProcessing.normalize([line(60, guide.baseline, 60, guide.xLine)], guide)!;
      final points = strokes.single;
      expect(points.first.x, closeTo(0, 1e-6));
      expect(points.first.y, closeTo(0, 1e-6));
      expect(points.last.y, closeTo(-1, 1e-6));
    });

    test('nothing written gives null', () {
      expect(GlyphProcessing.normalize([[]], guide), isNull);
    });

    test('straight lines are simplified to their ends', () {
      final strokes = GlyphProcessing.normalize([line(10, 100, 150, 100, n: 40)], guide)!;
      expect(strokes.single.length, 2);
    });

    test('fast strokes are thinner than slow ones', () {
      final slow = GlyphProcessing.penWidths(line(0, 0, 100, 0, seconds: 2));
      final fast = GlyphProcessing.penWidths(line(0, 0, 100, 0, seconds: 0.05));
      expect(fast[10], lessThan(slow[10]));
    });

    test('pressing harder makes the line wider', () {
      final points = [
        ...line(0, 0, 50, 0, n: 10, pressure: 0.2),
        ...line(50, 0, 100, 0, n: 10, pressure: 0.9).map((p) => CapturedPoint(p.x, p.y, p.time + 0.42, p.pressure)),
      ];
      final widths = GlyphProcessing.penWidths(points);
      expect(widths[16], greaterThan(widths[3]));
      // Without pressure the iPhone's speed-only widths are used.
      final noPressure = GlyphProcessing.penWidths(line(0, 0, 100, 0));
      expect(noPressure[10], closeTo(noPressure[9], 0.05));
    });
  });

  group('writing a handwriting profile with the pen', () {
    List<Stroke> letter(double top) => [
          [StrokePoint(0, 0, 1), StrokePoint(0, top, 1)],
          [StrokePoint(0, top, 1), StrokePoint(0.5, top, 1), StrokePoint(0.5, 0, 1)],
        ];

    test('first profile is the default, samples become glyphs', () {
      final library = HandwritingLibrary();
      final profile = library.createProfile('Meine Schrift');
      expect(library.defaultProfile!.uid, profile.uid);
      expect(library.createProfile('Zweite').isDefault, isFalse);

      library.addGlyph(profile.uid, 'n', letter(-1));
      library.addGlyph(profile.uid, 'n', letter(-1.1));
      library.addGlyph(profile.uid, 'h', letter(-1.8));
      expect(library.capturedCharacters(profile.uid), {'n', 'h'});
      expect(library.samples(profile.uid, 'n').length, 2);

      final font = library.font(profile.uid, 0.15);
      expect(font.variants('n')!.length, 2);
      expect(font.has('h'), isTrue);
      expect(font.has('a'), isFalse);
    });

    test('corrections and deleting a version', () {
      final library = HandwritingLibrary();
      final profile = library.createProfile('P');
      final sample = library.addGlyph(profile.uid, 'o', letter(-1));
      library.updateGlyph(sample.uid, scale: 1.3, baselineOffset: -0.1);
      expect(library.samples(profile.uid, 'o').single.scale, 1.3);
      expect(library.samples(profile.uid, 'o').single.baselineOffset, -0.1);
      library.deleteGlyph(sample.uid);
      expect(library.samples(profile.uid, 'o'), isEmpty);
    });

    test('the sample word measures the letter gap', () {
      final library = HandwritingLibrary();
      final profile = library.createProfile('P');
      for (final c in 'ab'.split('')) {
        library.addGlyph(profile.uid, c, letter(-1));
      }
      // Two letters 0.5 wide written 0.3 apart.
      final word = [...letter(-1), ...letter(-1).map((s) => [for (final p in s) StrokePoint(p.x + 0.8, p.y, p.w)])];
      final gap = library.measureSpacing(profile.uid, 'ab', word);
      expect(gap, closeTo(0.3, 0.001));
      expect(library.profile(profile.uid)!.spacingMeasured, isTrue);
      expect(library.measureSpacing(profile.uid, 'xyz', word), isNull);
    });

    test('pen strokes render as ink in a note', () {
      final library = HandwritingLibrary();
      final profile = library.createProfile('P');
      for (final c in 'mitose'.split('')) {
        library.addGlyph(profile.uid, c, letter(-1));
      }
      const settings = PageSettings();
      final pages = NoteLayout.layout(
        const NoteContent(title: '', header: '', body: 'mitose', seed: 3),
        settings,
        library.font(profile.uid, settings.penRatio),
      );
      expect(pages.single.ink, isNotEmpty);
      expect(pages.single.fallbacks.map((f) => f.text), ['1']); // only the page number
    });

    test('hints like on the iPhone', () {
      expect(HandwritingCharset.hint('a'), contains('gestrichelten'));
      expect(HandwritingCharset.hint('g'), contains('Unterlänge'));
      expect(HandwritingCharset.variantLetters.first, 'e');
    });
  });

  group('editor buttons (MarkupEditing)', () {
    test('heading on the line with the cursor', () {
      final edit = MarkupEditing.apply(LineStyle.heading, 'eins\nzwei\ndrei', 6, 6);
      expect(edit.text, 'eins\n# zwei\ndrei');
      expect(edit.caret, 'eins\n# zwei'.length);
    });

    test('a style replaces the old marker, on every selected line', () {
      final edit = MarkupEditing.apply(LineStyle.bullet, '# a\n> b\nc', 0, 7);
      expect(edit.text, '- a\n- b\nc');
      expect(MarkupEditing.apply(LineStyle.plain, '- [ ] x', 0, 0).text, 'x');
    });

    test('empty text gets the marker', () {
      expect(MarkupEditing.apply(LineStyle.callout, '', 0, 0).text, '> ');
    });

    test('checklist: add, tick, untick', () {
      var edit = MarkupEditing.toggleCheckbox('Hausaufgabe', 3, 3);
      expect(edit.text, '- [ ] Hausaufgabe');
      edit = MarkupEditing.toggleCheckbox(edit.text, 3, 3);
      expect(edit.text, '- [x] Hausaufgabe');
      edit = MarkupEditing.toggleCheckbox(edit.text, 3, 3);
      expect(edit.text, '- [ ] Hausaufgabe');
    });

    test('insert at the cursor or append after a blank line', () {
      expect(MarkupEditing.insert('---\n', 'ab', 1, 1).text, 'a---\nb');
      final appended = MarkupEditing.insert('[[Mitose]]', 'Text', -1, -1);
      expect(appended.text, 'Text\n\n[[Mitose]]');
      expect(appended.caret, appended.text.length);
    });
  });

  group('pages, links and flashcards (NotePages)', () {
    Note note(Store store, String title, {String body = '', String? subject}) =>
        Note(store.add(Kind.note, {'title': title, 'body': body, 'subject': ?subject}));

    test('subpages take the parent\'s subject and move up when the parent is deleted', () {
      final store = Store();
      final top = note(store, 'Biologie');
      final middle = store.addSubpage(top.uid, title: 'Zelle');
      store.update(top.rec, (d) => d['subject'] = 'S1');
      final child = store.addSubpage(middle.uid, title: 'Mitose');
      expect(store.note(child.uid)!.subject, isNull); // copied from "Zelle", which had none
      expect(store.childrenOf(top.uid).map((n) => n.title), ['Zelle']);
      expect(store.parentOf(child.uid)!.title, 'Zelle');
      expect(store.hiddenFromList(), containsAll([middle.uid, child.uid]));

      store.deleteNote(store.note(middle.uid)!);
      expect(store.parentOf(child.uid)!.title, 'Biologie');
      expect(store.note(middle.uid), isNull);
    });

    test('subpage copies subject', () {
      final store = Store();
      final parent = note(store, 'Mathe', subject: 'S9');
      expect(store.note(store.addSubpage(parent.uid).uid)!.subject, 'S9');
    });

    test('pin toggles', () {
      final store = Store();
      final a = note(store, 'A');
      store.togglePin(a.uid);
      expect(store.isPinned(a.uid), isTrue);
      expect(store.hiddenFromList(), contains(a.uid));
      store.togglePin(a.uid);
      expect(store.isPinned(a.uid), isFalse);
    });

    test('links, backlinks and missing pages ignore case and accents', () {
      final store = Store();
      final uebung = note(store, 'Übung');
      final source = note(store, 'Start', body: 'Siehe [[ubung]] und [[Neu]].');
      expect(store.linkedFrom(source).single.uid, uebung.uid);
      expect(store.backlinksTo(uebung).single.uid, source.uid);
      expect(store.missingLinks(source), ['Neu']);
      expect(sameTitle('  Mitose ', 'mitose'), isTrue);
      expect(sameTitle('Straße', 'strasse'), isTrue);
    });

    test('flashcards follow the note and keep their learning progress', () {
      final store = Store();
      final source = note(store, 'Vokabeln', body: 'house :: Haus\nlearn :: lernen', subject: 'S1');
      store.syncCards(source);
      var cards = store.cards.where((c) => c.note == source.uid).toList();
      expect(cards.length, 2);
      expect(cards.every((c) => c.subject == 'S1'), isTrue);

      final house = cards.firstWhere((c) => c.front == 'house');
      store.update(house.rec, (d) => d['ease'] = 2.9);
      store.update(source.rec, (d) => d['body'] = 'house :: das Haus\nnew :: neu');
      store.syncCards(store.note(source.uid)!);

      cards = store.cards.where((c) => c.note == source.uid).toList();
      expect(cards.map((c) => c.front).toSet(), {'house', 'new'});
      final updated = cards.firstWhere((c) => c.front == 'house');
      expect(updated.back, 'das Haus');
      expect(updated.ease, 2.9);
    });

    test('templates: vocabulary makes cards, every template can be laid out', () {
      final store = Store();
      final vocab = store.addFromTemplate(NoteTemplate.vocabulary);
      expect(vocab.title, 'Vokabeln');
      store.syncCards(vocab);
      expect(store.cards.where((c) => c.note == vocab.uid).length, 2);
      expect(store.metaOf(vocab.uid)!.rec.str('template'), 'vocabulary');

      final font = HandwritingFont(FontSource.empty, penRatio: 0.15);
      for (final template in NoteTemplate.values) {
        final pages = NoteLayout.layout(NoteContent(title: template.title, header: '', body: template.body, seed: 1),
            const PageSettings(), font);
        expect(pages, isNotEmpty);
      }
    });
  });
}
