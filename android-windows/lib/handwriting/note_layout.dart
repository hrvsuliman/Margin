// Lays a note out on A4 pages in the user's handwriting. Ported from NoteLayout.swift.
//
// Variation is deterministic: each word's look depends on the note's seed, the
// word itself and how often it already appeared. Editing one word therefore
// leaves the look of all other words unchanged.

import 'dart:math' as math;

import '../logic/markup.dart';
import 'geometry.dart';
import 'handwriting_font.dart';
import 'stroke_outline.dart';

enum PaperStyle {
  lined('Liniert', 8),
  squared('Kariert', 10),
  dotted('Gepunktet', 10),
  blank('Blanko', 9);

  const PaperStyle(this.title, this.defaultLineSpacing);
  final String title;

  /// Typical line pitch in millimetres.
  final double defaultLineSpacing;

  static PaperStyle parse(String? raw) => values.firstWhere((p) => p.name == raw, orElse: () => lined);
}

enum PenColor {
  royalBlue('Königsblau', 0x1F3FA0),
  black('Schwarz', 0x1E1E22),
  navy('Dunkelblau', 0x17264F),
  green('Grün', 0x1F6B45),
  red('Rot', 0xB3261E),
  violet('Lila', 0x5B3A8C);

  const PenColor(this.title, this.hex);
  final String title;
  final int hex;

  static PenColor parse(String? raw) => values.firstWhere((p) => p.name == raw, orElse: () => royalBlue);
}

/// Paper and pen settings, in PDF points (1 pt = 1/72 inch).
class PageSettings {
  const PageSettings({
    this.pageWidth = a4Width,
    this.pageHeight = a4Height,
    this.paper = PaperStyle.lined,
    this.lineSpacing = 22.677165354330707, // 8 mm
    this.writingSize = 1,
    this.penColor = PenColor.royalBlue,
    this.penWeight = 1,
    this.marginTop = 56.69291338582677, // 20 mm
    this.marginBottom = 42.51968503937008, // 15 mm
    this.marginLeft = 42.51968503937008, // 15 mm
    this.marginRight = 70.86614173228347, // 25 mm
    this.showMarginLine = true,
    this.showPageNumbers = true,
    this.showHeader = true,
    this.printPaper = true,
  });

  /// The page settings stored on a note record (`NoteDTO` fields).
  factory PageSettings.fromNote(Map<String, dynamic> data) {
    double number(String key, double fallback) => data[key] is num ? (data[key] as num).toDouble() : fallback;
    bool flag(String key) => data[key] is bool ? data[key] as bool : true;
    return PageSettings(
      paper: PaperStyle.parse(data['paper'] as String?),
      lineSpacing: mm(number('lineSpacingMM', 8)),
      writingSize: number('writingSize', 1),
      penColor: PenColor.parse(data['penColor'] as String?),
      penWeight: number('penWeight', 1),
      marginTop: mm(number('marginTopMM', 20)),
      marginBottom: mm(number('marginBottomMM', 15)),
      marginLeft: mm(number('marginLeftMM', 20)),
      marginRight: mm(number('marginRightMM', 15)),
      showMarginLine: flag('showMarginLine'),
      showPageNumbers: flag('showPageNumbers'),
      showHeader: flag('showHeader'),
      printPaper: flag('printPaper'),
    );
  }

  static const a4Width = 595.28;
  static const a4Height = 841.89;

  static double mm(double millimetres) => millimetres * 72 / 25.4;

  final double pageWidth;
  final double pageHeight;
  final PaperStyle paper;
  final double lineSpacing;
  final double writingSize;
  final PenColor penColor;
  final double penWeight;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;
  final bool showMarginLine;
  final bool showPageNumbers;
  final bool showHeader;
  final bool printPaper;

  /// Height of a lowercase "x" in points.
  double get xHeight => lineSpacing * 0.34 * writingSize;

  /// Pen width relative to the x-height.
  double get penRatio => 0.15 * penWeight;
  double get contentWidth => pageWidth - marginLeft - marginRight;
  int get linesPerPage => math.max(1, (pageHeight - marginTop - marginBottom) ~/ lineSpacing);
}

/// The text of a note, as plain values.
class NoteContent {
  const NoteContent({required this.title, required this.header, required this.body, required this.seed});
  final String title;

  /// Small line at the top right of page 1, e.g. "Mathematik · 02.11.2026".
  final String header;
  final String body;
  final int seed;
}

/// Text drawn with the fallback font (character not written yet).
class FallbackText {
  const FallbackText(this.text, this.origin, this.fontSize);
  final String text;

  /// Left end of the baseline.
  final Pt origin;
  final double fontSize;
}

class LaidOutPage {
  LaidOutPage(this.number, this.ink, this.fallbacks);
  final int number;

  /// All handwriting on the page, filled with the non-zero rule.
  final List<Polygon> ink;
  final List<FallbackText> fallbacks;
}

abstract final class NoteLayout {
  static List<LaidOutPage> layout(NoteContent content, PageSettings settings, HandwritingFont font) {
    final writer = _PageWriter(settings, font, content.seed);

    if (settings.showHeader && content.header.isNotEmpty) {
      writer.writeRightAligned(writer.normalize(content.header), 0.8);
      writer.nextLine();
    }
    final title = writer.normalize(content.title).trim();
    NoteBlock? previous;
    if (title.isNotEmpty) {
      writer.writeParagraph(title, 1.5, underline: true);
      writer.nextLine();
      previous = const BlankBlock();
    }

    final blocks = Markup.parse(writer.normalize(content.body));
    bool afterContent() => !writer.isAtPageTop && previous is! BlankBlock && previous != null;
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      switch (block) {
        case BlankBlock():
          writer.nextLine();
        case HeadingBlock(:final text):
          if (afterContent()) writer.nextLine();
          writer.writeParagraph(text, 1.4, underline: true);
        case SubheadingBlock(:final text):
          if (afterContent()) writer.nextLine();
          writer.writeParagraph(text, 1.15);
        case BulletBlock(:final text):
          writer.writeParagraph(text, 1, bullet: true);
        case CheckboxBlock(:final text, :final checked):
          writer.writeParagraph(text, 1, checkbox: checked);
        case CalloutBlock(:final text):
          writer.writeParagraph(text, 1, callout: true);
        case DividerBlock():
          writer.drawDivider();
        case TableRowBlock(:final cells):
          if (cells.isEmpty) break;
          // All rows of one table share the column count of its widest row.
          var columns = cells.length;
          var first = true;
          for (var i = index - 1; i >= 0 && blocks[i] is TableRowBlock; i--) {
            final other = (blocks[i] as TableRowBlock).cells;
            columns = math.max(columns, other.length);
            if (other.isNotEmpty) first = false;
          }
          for (var i = index + 1; i < blocks.length && blocks[i] is TableRowBlock; i++) {
            columns = math.max(columns, (blocks[i] as TableRowBlock).cells.length);
          }
          writer.writeTableRow(cells, columns, first);
        case ParagraphBlock(:final text):
          writer.writeParagraph(text, 1);
        case ImageBlock():
          // Note pictures stay on the iPhone for now (not synced in v1).
          break;
      }
      previous = block;
    }
    return writer.finish();
  }
}

List<String> _characters(String text) => [for (final r in text.runes) String.fromCharCode(r)];

class _Drift {
  const _Drift(this.amplitude, this.frequency, this.phase, this.slope, this.start);
  final double amplitude;
  final double frequency;
  final double phase;
  final double slope;
  final double start;
}

/// Mutable state while laying out one note.
class _PageWriter {
  _PageWriter(this.settings, this.font, this.seed);

  final PageSettings settings;
  final HandwritingFont font;
  final int seed;

  final _pages = <LaidOutPage>[];
  var _ink = InkPath();
  var _fallbacks = <FallbackText>[];
  var _line = 0;
  final _occurrences = <String, int>{};
  _Drift? _lineDrift;

  double get x => settings.xHeight;
  double get leftEdge => settings.marginLeft;
  double get rightEdge => settings.pageWidth - settings.marginRight;

  bool get isAtPageTop => _line == 0;

  static const _replacements = [
    ('…', '...'), ('·', '-'), ('•', '-'), ('—', '-'), ('–', '-'), ('‚', ','),
    ('‘', "'"), ('’', "'"), ('»', '"'), ('«', '"'), ('”', '“'),
  ];

  /// Characters without a glyph are replaced by close equivalents first.
  String normalize(String text) {
    var result = text
        .replaceAll('\t', '    ')
        // Decomposed umlauts (a + combining diaeresis) as single characters.
        .replaceAll('ä', 'ä').replaceAll('ö', 'ö').replaceAll('ü', 'ü')
        .replaceAll('Ä', 'Ä').replaceAll('Ö', 'Ö').replaceAll('Ü', 'Ü');
    for (final (from, to) in _replacements) {
      if (!font.has(from)) result = result.replaceAll(from, to);
    }
    if (!font.has('ß')) result = result.replaceAll('ß', 'ss');
    return result;
  }

  double _baseline(int line) => settings.marginTop + (line + 1) * settings.lineSpacing;

  void nextLine() {
    _line += 1;
    _lineDrift = null;
    if (_line >= settings.linesPerPage) _newPage();
  }

  void _newPage() {
    _closePage();
    _line = 0;
    _lineDrift = null;
  }

  void _closePage() {
    final number = _pages.length + 1;
    if (settings.showPageNumbers) {
      final text = '$number';
      final width = measure(text, 0.8);
      final baselineY = settings.pageHeight - settings.marginBottom / 2 + x * 0.4;
      final rng = SeededRandom(StableHash.combine([seed, 77, number]));
      _write(text, (settings.pageWidth - width) / 2, baselineY, 0.8, rng, drift: false);
    }
    _pages.add(LaidOutPage(number, _ink.polygons, _fallbacks));
    _ink = InkPath();
    _fallbacks = [];
  }

  List<LaidOutPage> finish() {
    if (_line > 0 || !_ink.isEmpty || _fallbacks.isNotEmpty || _pages.isEmpty) _closePage();
    return _pages;
  }

  // ------------------------------------------------------------ writing

  void writeRightAligned(String text, double scale) {
    final width = measure(text, scale);
    final rng = SeededRandom(StableHash.combine([seed, 11, StableHash.of(text)]));
    _write(text, math.max(leftEdge, rightEdge - width), _baseline(_line), scale, rng, drift: true);
  }

  /// Writes a paragraph with word wrap, then moves to the next line.
  /// [checkbox] draws a hand-drawn box (ticked when true); [callout] a bar along the left edge.
  void writeParagraph(String text, double scale,
      {bool underline = false, bool bullet = false, bool? checkbox, bool callout = false}) {
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty && checkbox == null) {
      nextLine();
      return;
    }
    final indent = checkbox != null
        ? x * 2.1
        : bullet
            ? x * 1.6
            : callout
                ? x * 1.5
                : 0.0;
    final spaceWidth = font.wordSpacing * x * scale;
    var lineStart = leftEdge + indent + _jitterIndent();
    var cursor = lineStart;
    var underlineStart = cursor;

    if (bullet) {
      final rng = SeededRandom(StableHash.combine([seed, 5, _line]));
      final marker = font.has('-') ? '-' : '•';
      _write(marker, leftEdge + x * 0.2, _baseline(_line), scale, rng, drift: true);
    }
    if (checkbox != null) _drawCheckbox(checkbox);
    if (callout) _drawCalloutBar();

    void finishLineUnderline() {
      if (underline && cursor > underlineStart) {
        _drawUnderline(underlineStart, cursor - spaceWidth * 0.6, _baseline(_line), scale);
      }
    }

    for (final word in words) {
      var pieces = [word];
      final available = rightEdge - lineStart;
      if (measure(word, scale) > available) pieces = _split(word, available, scale);
      for (final piece in pieces) {
        final width = measure(piece, scale);
        if (cursor + width > rightEdge && cursor > lineStart) {
          finishLineUnderline();
          nextLine();
          if (callout) _drawCalloutBar();
          lineStart = leftEdge + indent + _jitterIndent();
          cursor = lineStart;
          underlineStart = cursor;
        }
        final occurrence = _occurrences[piece] ?? 0;
        _occurrences[piece] = occurrence + 1;
        final rng = SeededRandom(StableHash.combine([seed, StableHash.of(piece), occurrence]));
        final advance = _write(piece, cursor, _baseline(_line), scale, rng, drift: true);
        cursor += advance + spaceWidth * (1 + 0.12 * font.variation * rng.signed());
      }
    }
    finishLineUnderline();
    nextLine();
  }

  double _jitterIndent() {
    final rng = SeededRandom(StableHash.combine([seed, 3, _pages.length, _line]));
    return x * 0.12 * font.variation * rng.unit();
  }

  /// Splits a word that is longer than a whole line.
  List<String> _split(String word, double maxWidth, double scale) {
    final pieces = <String>[];
    var current = '';
    for (final character in _characters(word)) {
      final candidate = current + character;
      if (current.isNotEmpty && measure(candidate, scale) > maxWidth) {
        pieces.add(current);
        current = character;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) pieces.add(current);
    return pieces;
  }

  /// Width of a word without random variation.
  double measure(String text, double scale) {
    var width = 0.0;
    for (final character in _characters(text)) {
      if (character == ' ') {
        width += (font.wordSpacing - font.letterSpacing) * x * scale;
        continue;
      }
      final variants = font.variants(character);
      if (variants != null && variants.isNotEmpty) {
        width += (variants.first.advance + font.letterSpacing) * x * scale;
      } else {
        width += FallbackFont.width(character, FallbackFont.size(x * scale)) + font.letterSpacing * x * scale;
      }
    }
    return math.max(0.0, width - font.letterSpacing * x * scale);
  }

  /// Draws a word and returns its width.
  double _write(String text, double start, double baselineY, double scale, SeededRandom rng, {required bool drift}) {
    final variation = font.variation;
    final shear = -math.tan(font.slant);
    var cursor = start;
    String? previousCharacter;
    var previousIndex = -1;
    var pendingFallback = '';
    var fallbackStart = cursor;

    void flushFallback() {
      if (pendingFallback.isEmpty) return;
      final size = FallbackFont.size(x * scale);
      final y = baselineY + (drift ? _drift(fallbackStart) : 0);
      _fallbacks.add(FallbackText(pendingFallback, Pt(fallbackStart, y), size));
      pendingFallback = '';
    }

    for (final character in _characters(text)) {
      if (character == ' ') {
        flushFallback();
        previousCharacter = null;
        cursor += (font.wordSpacing - font.letterSpacing) * x * scale;
        continue;
      }
      final options = font.variants(character);
      if (options == null || options.isEmpty) {
        if (pendingFallback.isEmpty) fallbackStart = cursor;
        pendingFallback += character;
        cursor += FallbackFont.width(character, FallbackFont.size(x * scale)) + font.letterSpacing * x * scale;
        continue;
      }
      flushFallback();

      var index = unsignedMod(rng.next(), options.length);
      if (previousCharacter == character && previousIndex == index && options.length > 1) {
        index = (index + 1) % options.length;
      }
      previousCharacter = character;
      previousIndex = index;
      final variant = options[index];

      final size = x * scale * (1 + 0.035 * variation * rng.soft());
      final rotation = 0.028 * variation * rng.soft();
      final lift = x * scale * 0.035 * variation * rng.soft();
      final y = baselineY + lift + (drift ? _drift(cursor) : 0);

      // shear → scale → rotate → move (CGAffineTransform concatenation order).
      final cosR = math.cos(rotation), sinR = math.sin(rotation);
      final dx = cursor;
      _ink.addAll(variant.outline, (p) {
        final sx = (p.x + shear * p.y) * size;
        final sy = p.y * size;
        return Pt(sx * cosR - sy * sinR + dx, sx * sinR + sy * cosR + y);
      });

      cursor += variant.advance * size + font.letterSpacing * x * scale * (1 + 0.25 * variation * rng.signed());
    }
    flushFallback();
    return math.max(0.0, cursor - start - font.letterSpacing * x * scale);
  }

  /// Slow up-and-down movement along a line, like writing without a ruler.
  double _drift(double position) {
    var d = _lineDrift;
    if (d == null) {
      final rng = SeededRandom(StableHash.combine([seed, 101, _pages.length, _line]));
      final strength = font.variation;
      final amplitude = x * 0.06 * strength * rng.unit();
      final frequency = 0.6 + rng.unit() * 0.8;
      final phase = rng.unit() * 2 * math.pi;
      final slope = 0.006 * strength * rng.signed();
      d = _lineDrift = _Drift(amplitude, frequency, phase, slope, leftEdge);
    }
    final t = (position - d.start) / math.max(settings.contentWidth, 1.0);
    return d.amplitude * math.sin(d.phase + t * 2 * math.pi * d.frequency) + d.slope * (position - d.start);
  }

  // ------------------------------------------------------------ drawn shapes

  /// A slightly bowed pen line, like one drawn without a ruler.
  void _stroke(Pt start, Pt end, int salt) {
    final rng = SeededRandom(StableHash.combine([seed, salt, _pages.length, _line]));
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.max(math.sqrt(dx * dx + dy * dy), 1.0);
    final normal = Pt(-dy / length, dx / length);
    final bow = math.min(x * 0.12, length * 0.02) * font.variation * rng.signed();
    final steps = math.max(3, math.min(10, length ~/ (x * 1.5)));
    final points = <Pt>[];
    final widths = <double>[];
    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final wobble = bow * math.sin(t * math.pi) + x * 0.015 * font.variation * rng.soft();
      points.add(Pt(start.x + dx * t + normal.x * wobble, start.y + dy * t + normal.y * wobble));
      widths.add(x * font.penRatio * (0.85 + 0.15 * rng.unit()));
    }
    StrokeOutline.add(points, widths, _ink);
  }

  void _drawCheckbox(bool checked) {
    final b = _baseline(_line) + _drift(leftEdge);
    final size = x * 1.15;
    final left = leftEdge + x * 0.15;
    final top = b - size * 0.98;
    final o = size * 0.08;
    _stroke(Pt(left - o, top), Pt(left + size + o, top + o * 0.3), 601);
    _stroke(Pt(left + size, top - o), Pt(left + size - o * 0.3, top + size + o), 602);
    _stroke(Pt(left + size + o, top + size), Pt(left - o, top + size - o * 0.3), 603);
    _stroke(Pt(left, top + size + o), Pt(left + o * 0.3, top - o), 604);
    if (checked) {
      _stroke(Pt(left + size * 0.15, top + size * 0.5), Pt(left + size * 0.45, top + size * 0.85), 605);
      _stroke(Pt(left + size * 0.45, top + size * 0.85), Pt(left + size * 1.15, top - size * 0.25), 606);
    }
  }

  /// One line's piece of the bar next to a "> " callout.
  void _drawCalloutBar() {
    final b = _baseline(_line);
    final barX = leftEdge + x * 0.45;
    _stroke(Pt(barX, b - settings.lineSpacing * 0.78), Pt(barX, b + settings.lineSpacing * 0.2), 701);
  }

  void drawDivider() {
    final y = _baseline(_line) - settings.lineSpacing * 0.4;
    final inset = settings.contentWidth * 0.12;
    _stroke(Pt(leftEdge + inset, y), Pt(rightEdge - inset, y + x * 0.05), 801);
    nextLine();
  }

  /// A table row on one ruled line: cells shrink to fit their column, lines between them.
  void writeTableRow(List<String> cells, int columnCount, bool first) {
    final columns = math.max(columnCount, 1);
    final width = settings.contentWidth / columns;
    final b = _baseline(_line);
    final top = b - settings.lineSpacing * 0.8;
    final bottom = b + settings.lineSpacing * 0.2;
    if (first) _stroke(Pt(leftEdge, top), Pt(rightEdge, top), 901);
    for (var index = 0; index < math.min(cells.length, columns); index++) {
      final available = width - x * 0.8;
      var text = cells[index];
      var scale = 1.0;
      final measured = measure(text, 1);
      if (measured > available) scale = math.max(0.6, available / measured);
      while (_characters(text).length > 2 && measure(text, scale) > available) {
        final chars = _characters(text);
        text = '${chars.sublist(0, chars.length - 2).join()}.';
      }
      if (text.isEmpty) continue;
      final rng = SeededRandom(StableHash.combine([seed, 31, StableHash.of(text), index]));
      _write(text, leftEdge + index * width + x * 0.4, b, scale, rng, drift: false);
    }
    for (var index = 1; index < columns; index++) {
      final lineX = leftEdge + index * width;
      _stroke(Pt(lineX, top), Pt(lineX, bottom), 902 + index);
    }
    _stroke(Pt(leftEdge, bottom), Pt(rightEdge, bottom), 950);
    nextLine();
  }

  void _drawUnderline(double start, double end, double baselineY, double scale) {
    if (end <= start) return;
    final rng = SeededRandom(StableHash.combine([seed, 404, _pages.length, _line]));
    final y = baselineY + x * 0.38 * scale;
    const steps = 8;
    final points = <Pt>[];
    final widths = <double>[];
    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final px = start - x * 0.1 + (end - start + x * 0.2) * t;
      points.add(Pt(px, y + _drift(px) + x * 0.035 * font.variation * rng.soft() + t * x * 0.05 * rng.signed()));
      widths.add(x * font.penRatio * (0.9 + 0.15 * rng.unit()));
    }
    StrokeOutline.add(points, widths, _ink);
  }
}
