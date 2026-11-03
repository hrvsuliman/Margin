import 'package:flutter_test/flutter_test.dart';
import 'package:margin/logic/homework_parser.dart';
import 'package:margin/logic/learning.dart';
import 'package:margin/logic/markup.dart';
import 'package:margin/logic/pin_links.dart';

void main() {
  group('markup (as NoteBlock.parse on the iPhone)', () {
    test('line types', () {
      final blocks = Markup.parse('# Zellen\n## Aufbau\n- Kern\n- [ ] lernen\n- [x] lesen\n> Merke\n| a | b |\n|---|---|\n---\n\nText [[Mitose]]');
      expect(blocks[0], isA<HeadingBlock>());
      expect(blocks[1], isA<SubheadingBlock>());
      expect((blocks[2] as BulletBlock).text, 'Kern');
      expect((blocks[3] as CheckboxBlock).checked, isFalse);
      expect((blocks[4] as CheckboxBlock).checked, isTrue);
      expect((blocks[5] as CalloutBlock).text, 'Merke');
      expect((blocks[6] as TableRowBlock).cells, ['a', 'b']);
      expect((blocks[7] as TableRowBlock).cells, isEmpty);
      expect(blocks[8], isA<DividerBlock>());
      expect(blocks[9], isA<BlankBlock>());
      expect((blocks[10] as ParagraphBlock).text, 'Text Mitose');
    });

    test('links and flashcards', () {
      expect(Markup.links('[[Mitose]] und [[mitose]] und [[Bild:X]] [[Meiose]]'), ['Mitose', 'Meiose']);
      expect(Markup.flashcards('- Mitose :: Zellteilung\nkein Paar\n:: leer\n# Kern :: Steuerzentrale'), [
        ('Mitose', 'Zellteilung'),
        ('Kern', 'Steuerzentrale'),
      ]);
      expect(Markup.toggleCheckbox('a\n  - [ ] b', 1), 'a\n  - [x] b');
    });
  });

  group('SM-2 (as SpacedRepetition on the iPhone)', () {
    final now = DateTime(2026, 11, 3, 15);
    test('first reviews', () {
      final first = SpacedRepetition.review(CardSchedule(due: now), ReviewGrade.good, now);
      expect(first.intervalDays, 1);
      expect(first.repetitions, 1);
      expect(first.due, DateTime(2026, 11, 4));
      final second = SpacedRepetition.review(first, ReviewGrade.good, now);
      expect(second.intervalDays, 4);
      final third = SpacedRepetition.review(second, ReviewGrade.good, now);
      expect(third.intervalDays, (4 * second.ease).round());
      expect(SpacedRepetition.review(CardSchedule(due: now), ReviewGrade.easy, now).intervalDays, 3);
    });

    test('again resets and lowers the ease, never below 1.3', () {
      var card = CardSchedule(ease: 1.4, intervalDays: 10, repetitions: 4, due: now);
      card = SpacedRepetition.review(card, ReviewGrade.again, now);
      expect(card.repetitions, 0);
      expect(card.lapses, 1);
      expect(card.ease, 1.3);
      expect(card.due, now.add(const Duration(minutes: 10)));
    });

    test('readiness', () {
      final (overall, topics) = Readiness.evaluate([
        const ReadinessInput(id: 'a', understanding: 4, completion: 1, scores: [1]),
        const ReadinessInput(id: 'b'),
      ], now);
      expect(topics.first.score, closeTo(1, 0.001));
      expect(topics.last.score, 0);
      expect(overall, closeTo(0.5, 0.001));
    });
  });

  group('homework parser (as HomeworkParser on the iPhone)', () {
    final tuesday = DateTime(2026, 11, 3);
    test('weekday, subject and title', () {
      final s = HomeworkParser.suggest('Mathe: S. 34 Nr. 5a bis Freitag', ['Mathematik', 'Deutsch'], today: tuesday);
      expect(s.title, 'Mathe: S. 34 Nr. 5a bis Freitag');
      expect(s.subjectName, 'Mathematik');
      expect(s.dueDate, DateTime(2026, 11, 6));
    });

    test('dates', () {
      expect(HomeworkParser.dueDate('bis 12.11.', tuesday), DateTime(2026, 11, 12));
      expect(HomeworkParser.dueDate('bis 2.1.', tuesday), DateTime(2027, 1, 2));
      expect(HomeworkParser.dueDate('Vokabeln für morgen', tuesday), DateTime(2026, 11, 4));
      expect(HomeworkParser.dueDate('übermorgen abgeben', tuesday), DateTime(2026, 11, 5));
      expect(HomeworkParser.dueDate('bis Dienstag', tuesday), DateTime(2026, 11, 10));
      expect(HomeworkParser.dueDate('nichts', tuesday), isNull);
    });

    test('title cleanup', () {
      expect(HomeworkParser.cleanTitle('HA: Buch S. 12'), 'Buch S. 12');
      expect(HomeworkParser.cleanTitle('x ' * 50).endsWith(' …'), isTrue);
    });
  });

  test('YouTube links', () {
    expect(PinLinks.youTubeId(Uri.parse('https://www.youtube.com/watch?v=abc123')), 'abc123');
    expect(PinLinks.youTubeId(Uri.parse('https://youtu.be/xyz')), 'xyz');
    expect(PinLinks.youTubeId(Uri.parse('https://youtube.com/shorts/s1')), 's1');
    expect(PinLinks.youTubeId(Uri.parse('https://example.com/watch?v=1')), isNull);
    expect(PinLinks.parse('simpleclub.com/mathe')?.host, 'simpleclub.com');
    expect(PinLinks.parse('kein link'), isNull);
    expect(PinLinks.htmlTitle('<html><title> Zellen &amp; Co </title>'), 'Zellen & Co');
  });
}
