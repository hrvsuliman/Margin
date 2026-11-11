import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:margin/data/backup_import.dart';
import 'package:margin/data/entities.dart';
import 'package:margin/data/store.dart';
import 'package:margin/handwriting/analysis.dart';
import 'package:margin/handwriting/geometry.dart';
import 'package:margin/handwriting/handwriting_font.dart';
import 'package:margin/handwriting/handwriting_library.dart';
import 'package:margin/handwriting/note_layout.dart';
import 'package:margin/handwriting/pdf_export.dart';

/// A pen-on-paper outline (glyph format version 2): a box from the baseline up to [top].
Stroke box({double width = 0.6, double top = -1, double bottom = 0}) => [
      StrokePoint(0, bottom, 0),
      StrokePoint(width, bottom, 0),
      StrokePoint(width, top, 0),
      StrokePoint(0, top, 0),
    ];

GlyphInput glyph(String uid, {double top = -1, double width = 0.6}) =>
    GlyphInput(uid: uid, outlines: [box(top: top, width: width)]);

/// Every lowercase letter, digit and some punctuation written once.
FontSource sampleSource({double xTop = -1}) {
  final glyphs = <String, List<GlyphInput>>{};
  for (final c in 'abcdefghijklmnopqrstuvwxyz'.split('')) {
    final ascender = 'bdfhklt'.contains(c);
    glyphs[c] = [glyph('g-$c', top: ascender ? xTop * 1.7 : xTop)];
  }
  for (final c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,-:'.split('')) {
    glyphs[c] = [glyph('g-$c', top: '.,-:'.contains(c) ? -0.3 : xTop * 1.7)];
  }
  return FontSource(glyphs: glyphs);
}

List<Pt> allPoints(LaidOutPage page) => [for (final p in page.ink) ...p];

void main() {
  group('random numbers and hashes (same values as the iPhone)', () {
    test('SplitMix64 like SeededRandom in Swift', () {
      final rng = SeededRandom(1);
      expect([rng.next(), rng.next(), rng.next()], [-4689498862643123097, -534904783426661026, 8196980753821780235]);
      final units = SeededRandom(42);
      expect(units.unit(), closeTo(0.1599103928769201, 1e-15));
      expect(units.unit(), closeTo(0.27860113025513866, 1e-15));
      expect(SeededRandom(-5).next(), -8161798454662654712);
    });

    test('FNV-1a and combine like StableHash', () {
      expect(StableHash.of('Handschrift'), 8237828559866158505);
      expect(StableHash.of('Zwölf'), 8856444070758061265);
      expect(StableHash.combine([1, 77, 2]), 1188665271124065898);
      expect(StableHash.combine([StableHash.of('a'), 5, 0]), -5928643816302980609);
    });

    test('modulo treats values as unsigned', () {
      final rng = SeededRandom(9);
      for (var i = 0; i < 200; i++) {
        final value = rng.next();
        for (final n in [1, 2, 3, 7, 10]) {
          final expected = (BigInt.from(value).toUnsigned(64) % BigInt.from(n)).toInt();
          expect(unsignedMod(value, n), expected);
        }
      }
    });
  });

  group('glyph storage (GlyphStrokes)', () {
    test('strokes round trip', () {
      final strokes = [
        [const StrokePoint(0, 0, 1), const StrokePoint(0.5, -1.25, 0.75)],
        [const StrokePoint(0.25, -0.5, 1.5)],
      ];
      final decoded = GlyphStrokes.decodeGlyph(GlyphStrokes.encode(strokes));
      expect(decoded.outlines, isEmpty);
      expect(decoded.strokes.length, 2);
      expect(decoded.strokes[0][1].x, 0.5);
      expect(decoded.strokes[0][1].y, -1.25);
      expect(decoded.strokes[0][1].w, 0.75);
      expect(decoded.strokes[1].single.w, 1.5);
    });

    test('outlines from base64 as in an iPhone backup', () {
      final data = base64Encode(GlyphStrokes.encodeOutlines([box()]));
      final decoded = GlyphStrokes.decodeBase64(data);
      expect(decoded.strokes, isEmpty);
      expect(decoded.outlines.single.length, 4);
      expect(GlyphStrokes.decodeBase64('kein base64!').outlines, isEmpty);
    });

    test('broken data gives what could be read', () {
      final bytes = GlyphStrokes.encode([
        [const StrokePoint(1, 2, 3)],
      ]);
      expect(GlyphStrokes.decodeGlyph(bytes.sublist(0, bytes.length - 2)).strokes, isEmpty);
    });
  });

  group('analysis and font', () {
    test('writing smaller than the guide is scaled up', () {
      final analysis = HandwritingAnalysis.analyze(sampleSource(xTop: -0.8).glyphs);
      expect(analysis.scaleCorrection, closeTo(1.25, 0.001));
      expect(analysis.baselineCorrection, 0);
      expect(analysis.missing, contains('ä'));
    });

    test('a single tall letter is an outlier', () {
      final glyphs = sampleSource().glyphs;
      glyphs['o'] = [glyph('big-o', top: -1.8)];
      final analysis = HandwritingAnalysis.analyze(glyphs);
      expect(analysis.outliers.map((o) => o.character), contains('o'));
    });

    test('missing umlaut is built from the base letter', () {
      final font = HandwritingFont(sampleSource(), penRatio: 0.15);
      final a = font.variants('a')!.single;
      final ae = font.variants('ä')!.single;
      expect(ae.advance, a.advance);
      expect(ae.outline.length, a.outline.length + 2);
      expect(font.has('“'), isFalse);
    });
  });

  group('layout (NoteLayout)', () {
    const settings = PageSettings();
    final font = HandwritingFont(sampleSource(), penRatio: settings.penRatio);

    test('is deterministic and depends on the seed', () {
      const content = NoteContent(title: 'Zellen', header: 'Biologie', body: 'die zelle teilt sich', seed: 5);
      final a = NoteLayout.layout(content, settings, font);
      final b = NoteLayout.layout(content, settings, font);
      expect(allPoints(a.first).map((p) => p.toString()), allPoints(b.first).map((p) => p.toString()));
      final other = NoteLayout.layout(
        const NoteContent(title: 'Zellen', header: 'Biologie', body: 'die zelle teilt sich', seed: 6),
        settings,
        font,
      );
      expect(allPoints(other.first).first.toString(), isNot(allPoints(a.first).first.toString()));
    });

    test('long text flows onto more pages and stays inside the margins', () {
      final body = List.filled(400, 'zellteilung mitose meiose').join(' ');
      final pages = NoteLayout.layout(NoteContent(title: '', header: '', body: body, seed: 1), settings, font);
      expect(pages.length, greaterThan(1));
      expect([for (final p in pages) p.number], List.generate(pages.length, (i) => i + 1));
      final slack = settings.xHeight * 1.5;
      for (final page in pages) {
        for (final point in allPoints(page)) {
          expect(point.x, inInclusiveRange(settings.marginLeft - slack, settings.pageWidth - settings.marginRight + slack));
          expect(point.y, inInclusiveRange(0, settings.pageHeight));
        }
      }
    });

    test('without handwriting everything uses the fallback font', () {
      final empty = HandwritingFont(FontSource.empty, penRatio: settings.penRatio);
      final pages = NoteLayout.layout(const NoteContent(title: '', header: '', body: 'Hallo Welt', seed: 1), settings, empty);
      expect(pages.single.ink, isEmpty);
      expect(pages.single.fallbacks.map((f) => f.text), containsAll(['Hallo', 'Welt', '1']));
    });

    test('checkboxes, tables and dividers are drawn in ink', () {
      final empty = HandwritingFont(FontSource.empty, penRatio: settings.penRatio);
      final pages = NoteLayout.layout(
        const NoteContent(title: '', header: '', body: '- [x] fertig\n| a | b |\n|---|---|\n| c | d |\n---', seed: 1),
        settings,
        empty,
      );
      expect(pages.single.ink.length, greaterThan(8));
    });

    test('page settings come from the note record', () {
      final s = PageSettings.fromNote({...defaultsFor(Kind.note), 'paper': 'squared', 'lineSpacingMM': 10, 'penColor': 'red'});
      expect(s.paper, PaperStyle.squared);
      expect(s.penColor, PenColor.red);
      expect(s.lineSpacing, closeTo(28.346, 0.001));
      expect(s.marginLeft, closeTo(PageSettings.mm(20), 1e-9));
    });

    test('PDF has one A4 page per laid-out page', () async {
      final body = List.filled(400, 'zellteilung mitose meiose').join(' ');
      final pages = NoteLayout.layout(NoteContent(title: 'Bio', header: '', body: body, seed: 1), settings, font);
      final bytes = await NotePdf.build(pages, settings, title: 'Bio', compress: false);
      final text = latin1.decode(bytes);
      expect(text.startsWith('%PDF'), isTrue);
      expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(text).length, pages.length);
    });
  });

  group('iPhone backup import', () {
    Map<String, dynamic> backup() => {
          'format': 'margin-backup',
          'version': 5,
          'profiles': [
            {
              'uid': 'P1', 'name': 'Meine Schrift', 'isDefault': true, 'createdAt': '2026-11-01T10:00:00Z',
              'letterSpacing': 0.14, 'wordSpacing': 0.75, 'slantAdjust': 0, 'variation': 1, 'spacingMeasured': true,
            },
          ],
          'glyphs': [
            for (final c in ['a', 'b', 'c'])
              {
                'uid': 'G-$c', 'character': c, 'strokes': base64Encode(GlyphStrokes.encodeOutlines([box()])),
                'createdAt': '2026-11-01T10:00:00Z', 'scale': 1, 'baselineOffset': 0, 'profile': 'P1',
              },
          ],
          'notes': [
            {...defaultsFor(Kind.note), 'uid': 'N1', 'title': 'Mitose', 'body': 'abc'},
            {...defaultsFor(Kind.note), 'uid': 'N2', 'title': 'Schon da'},
          ],
        };

    test('rejects other files', () {
      expect(() => BackupImport.parse('{"format":"etwas"}'), throwsFormatException);
      expect(() => BackupImport.parse('kein json'), throwsFormatException);
      expect(() => BackupImport.parse('{"format":"margin-backup","version":9}'), throwsFormatException);
    });

    test('takes handwriting and new notes, keeps notes that are here', () {
      final store = Store();
      store.create(Kind.note, {...defaultsFor(Kind.note), 'uid': 'N2', 'title': 'Hier geändert'});
      final library = HandwritingLibrary();
      final summary = BackupImport.apply(BackupImport.parse(jsonEncode(backup())), store, library);

      expect(summary.profiles, 1);
      expect(summary.glyphs, 3);
      expect(summary.notes, 1);
      expect(summary.skippedNotes, 1);
      expect(store.note('N1')!.title, 'Mitose');
      expect(store.note('N2')!.title, 'Hier geändert');
      expect(library.defaultProfile!.name, 'Meine Schrift');
      expect(library.characterCount('P1'), 3);

      final font = library.font('P1', 0.15);
      expect(font.has('a'), isTrue);
      expect(font.has('z'), isFalse);
    });

    test('importing again replaces the profile and keeps this device\'s default', () {
      final library = HandwritingLibrary();
      library.importProfiles({
        'profiles': [
          {'uid': 'LOCAL', 'name': 'Hier', 'isDefault': true, 'createdAt': '2026-10-01T10:00:00Z'},
        ],
      });
      library.importProfiles(backup());
      library.importProfiles(backup());
      expect(library.profiles.length, 2);
      expect(library.defaultProfile!.uid, 'LOCAL');
      expect(library.characterCount('P1'), 3);
      expect(library.profileFor('P1')!.name, 'Meine Schrift');
      expect(library.profileFor('UNBEKANNT')!.uid, 'LOCAL');
    });
  });
}
