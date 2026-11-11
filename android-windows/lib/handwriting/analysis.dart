// The characters of a handwriting profile and what the app learns from the
// written samples. Ported from HandwritingCharset.swift and HandwritingAnalysis.swift.

import 'dart:math' as math;

import 'geometry.dart';

List<String> _chars(String s) => [for (final r in s.runes) String.fromCharCode(r)];

/// The characters a handwriting profile is built from, in capture order.
abstract final class HandwritingCharset {
  static final lowercase = _chars('abcdefghijklmnopqrstuvwxyzäöüß');
  static final uppercase = _chars('ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ');
  static final digits = _chars('0123456789');
  static const punctuation = ['.', ',', ';', ':', '!', '?', '-', '(', ')', '„', '“', '"', "'", '/', '+', '=', '%', '€', '&'];

  static final all = [...lowercase, ...uppercase, ...digits, ...punctuation];

  static final groups = <(String, List<String>)>[
    ('Kleinbuchstaben', lowercase),
    ('Großbuchstaben', uppercase),
    ('Ziffern', digits),
    ('Satzzeichen', punctuation),
  ];

  /// The most frequent German letters. Writing extra versions of these makes
  /// repeated text look the least mechanical.
  static final variantLetters = _chars('enisratdhulcgmo');

  /// Written once to measure the natural gap between letters.
  static const sampleWord = 'Handschrift';

  /// Hint shown while writing a character.
  static String hint(String character) {
    if (xHeightLetters.contains(character)) return 'Von der Grundlinie bis zur gestrichelten Linie.';
    if (capitalLetters.contains(character)) return 'Großbuchstabe: bis zur oberen Linie.';
    if (digits.contains(character)) return 'Ziffer: etwa so hoch wie ein Großbuchstabe.';
    if ('gjpqy'.contains(character)) return 'Unterlänge: unter die Grundlinie.';
    if ('bdfhklt'.contains(character)) return 'Oberlänge: über die gestrichelte Linie.';
    if (punctuation.contains(character)) return 'So groß und so hoch, wie du es im Text schreibst.';
    return 'Schreib so, wie du es auch im Heft schreibst.';
  }

  /// Letters that sit between baseline and x-height line.
  static final xHeightLetters = _chars('acemnorsuvwxz').toSet();

  /// Characters whose ink ends on the baseline (no descender).
  static final baselineCharacters = {
    ...xHeightLetters,
    ..._chars('bdhiklt'),
    ..._chars('ABCDEFGHIKLMNOPRSTUVWXYZ'),
    ...digits,
  };

  static final capitalLetters = uppercase.toSet();

  /// German pangram (contains ä, ö, ü and ß) for previews.
  static const pangram = 'Zwölf Boxkämpfer jagen Viktor quer über den großen Sylter Deich.';
}

/// One written sample, decoded.
class GlyphInput {
  const GlyphInput({
    required this.uid,
    this.strokes = const [],
    this.outlines = const [],
    this.scale = 1,
    this.baselineOffset = 0,
  });

  final String uid;

  /// Finger-written centre lines.
  final List<Stroke> strokes;

  /// Filled outlines traced from a pen sample on paper.
  final List<Stroke> outlines;
  final double scale;
  final double baselineOffset;

  GlyphBounds? get bounds => GlyphBounds.of([...strokes, ...outlines]);
}

/// Everything needed to build a `HandwritingFont`, as plain values.
class FontSource {
  const FontSource({
    this.glyphs = const {},
    this.letterSpacing = 0.14,
    this.wordSpacing = 0.75,
    this.slantAdjust = 0,
    this.variation = 1,
  });

  static const empty = FontSource();

  final Map<String, List<GlyphInput>> glyphs;
  final double letterSpacing;
  final double wordSpacing;
  final double slantAdjust;
  final double variation;
}

class Outlier {
  const Outlier({required this.character, required this.glyphUid, required this.ratio, required this.suggestedScale});
  final String character;
  final String glyphUid;

  /// Height compared to similar characters (1 = typical).
  final double ratio;

  /// Scale that would bring it in line.
  final double suggestedScale;
}

/// How big and where the user actually wrote compared to the guide lines, the
/// natural slant, and which characters stand out. Size and baseline corrections
/// are applied automatically when rendering.
class HandwritingAnalysis {
  int captured = 0;
  int total = HandwritingCharset.all.length;
  List<String> missing = HandwritingCharset.all;
  int variantCount = 0;

  /// Multiply raw sample coordinates by this so x-height letters are exactly 1 high.
  double scaleCorrection = 1;

  /// Raw y of the median baseline (subtract before scaling).
  double baselineCorrection = 0;

  /// Natural slant of the samples in degrees (positive leans right).
  double slantDegrees = 0;

  /// How evenly sized the x-height letters are (0 = very uneven … 1 = perfectly even).
  double consistency = 1;
  List<Outlier> outliers = [];

  static HandwritingAnalysis analyze(Map<String, List<GlyphInput>> glyphs) {
    final result = HandwritingAnalysis();
    bool has(String c) => glyphs[c]?.isNotEmpty ?? false;
    result.captured = HandwritingCharset.all.where(has).length;
    result.missing = HandwritingCharset.all.where((c) => !has(c)).toList();
    result.variantCount = glyphs.values.fold(0, (sum, list) => sum + list.length);

    // Baseline: where the ink of baseline characters ends.
    final bottoms = [
      for (final entry in glyphs.entries)
        if (HandwritingCharset.baselineCharacters.contains(entry.key))
          for (final input in entry.value)
            if (input.bounds case final b?) b.maxY,
    ];
    final bottom = median(bottoms);
    if (bottom != null) result.baselineCorrection = bottom.clamp(-0.5, 0.5);

    // Size: how tall x-height letters really are.
    final xTops = _topRatios(glyphs, HandwritingCharset.xHeightLetters, result.baselineCorrection);
    final medianTop = median([for (final e in xTops) e.top]);
    if (medianTop != null && medianTop > 0.1) {
      result.scaleCorrection = (1 / medianTop).clamp(0.6, 1.7);
      final deviations = [for (final e in xTops) (e.top / medianTop - 1).abs()];
      result.consistency = math.max(0.0, 1 - (median(deviations) ?? 0) * 3);
      result.outliers.addAll(_outliers(xTops, medianTop));
    }

    final capTops = _topRatios(glyphs, HandwritingCharset.capitalLetters, result.baselineCorrection);
    final medianCap = median([for (final e in capTops) e.top]);
    if (medianCap != null && medianCap > 0.1) result.outliers.addAll(_outliers(capTops, medianCap));

    result.slantDegrees = _slant(glyphs);
    return result;
  }

  static Iterable<Outlier> _outliers(List<_TopEntry> entries, double medianTop) sync* {
    for (final entry in entries) {
      final ratio = entry.top / medianTop;
      if (ratio < 0.72 || ratio > 1.35) {
        yield Outlier(character: entry.character, glyphUid: entry.uid, ratio: ratio, suggestedScale: entry.scale / ratio);
      }
    }
  }

  /// Height above the baseline for each sample of the given characters, including manual scale.
  static List<_TopEntry> _topRatios(Map<String, List<GlyphInput>> glyphs, Set<String> characters, double baseline) => [
        for (final entry in glyphs.entries)
          if (characters.contains(entry.key))
            for (final input in entry.value)
              if (input.bounds case final b?)
                _TopEntry(entry.key, input.uid, (baseline - b.minY) * input.scale, input.scale),
      ];

  /// Average lean of mostly vertical stroke segments.
  static double _slant(Map<String, List<GlyphInput>> glyphs) {
    var weighted = 0.0;
    var totalLength = 0.0;
    for (final input in glyphs.values.expand((list) => list)) {
      for (final stroke in [...input.strokes, ...input.outlines]) {
        for (var i = 1; i < stroke.length; i++) {
          var dx = stroke[i].x - stroke[i - 1].x;
          var dy = stroke[i].y - stroke[i - 1].y;
          final length = math.sqrt(dx * dx + dy * dy);
          if (length <= 0.05 || dy.abs() <= 2 * dx.abs()) continue;
          if (dy > 0) {
            // always measure upwards
            dx = -dx;
            dy = -dy;
          }
          weighted += math.atan2(dx, -dy) * length;
          totalLength += length;
        }
      }
    }
    if (totalLength <= 0) return 0;
    return weighted / totalLength * 180 / math.pi;
  }

  /// Letter gap measured from the sample word, in x-heights. Null if a letter
  /// of the word hasn't been written yet.
  static double? letterSpacing(String word, List<Stroke> written, Map<String, List<GlyphInput>> glyphs) {
    final analysis = analyze(glyphs);
    final wordBounds = GlyphBounds.of(written);
    if (wordBounds == null) return null;
    final letters = _chars(word);
    if (letters.length <= 1) return null;
    var glyphWidths = 0.0;
    for (final letter in letters) {
      final list = glyphs[letter];
      final bounds = list == null || list.isEmpty ? null : list.first.bounds;
      if (bounds == null) return null;
      glyphWidths += bounds.width * list!.first.scale;
    }
    final gap = (wordBounds.width - glyphWidths) / (letters.length - 1) * analysis.scaleCorrection;
    return gap.clamp(0.02, 0.9);
  }

  static double? median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isEven ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
  }
}

class _TopEntry {
  const _TopEntry(this.character, this.uid, this.top, this.scale);
  final String character;
  final String uid;
  final double top;
  final double scale;
}
