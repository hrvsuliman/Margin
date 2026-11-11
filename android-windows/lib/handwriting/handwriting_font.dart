// The user's handwriting, ready to draw. Ported from HandwritingFont.swift.

import 'dart:math' as math;

import 'analysis.dart';
import 'geometry.dart';
import 'stroke_outline.dart';

class GlyphVariant {
  const GlyphVariant(this.outline, this.advance);

  /// Filled ink in x-height units (baseline at y = 0, x-height at y = −1).
  final List<Polygon> outline;

  /// Ink width in x-heights.
  final double advance;
}

/// Every written sample becomes a filled outline. Immutable once built.
class HandwritingFont {
  HandwritingFont(FontSource source, {required this.penRatio})
      : analysis = HandwritingAnalysis.analyze(source.glyphs),
        letterSpacing = source.letterSpacing,
        wordSpacing = source.wordSpacing,
        slant = source.slantAdjust * math.pi / 180,
        variation = source.variation {
    final built = <String, List<GlyphVariant>>{};
    for (final entry in source.glyphs.entries) {
      if (entry.key.runes.length != 1) continue;
      final list = [
        for (final input in entry.value)
          if (makeVariant(input, analysis, penRatio) case final v?) v,
      ];
      if (list.isNotEmpty) built[entry.key] = list;
    }
    _addComposites(built, penRatio);
    _table = built;
  }

  final HandwritingAnalysis analysis;
  final double letterSpacing;
  final double wordSpacing;

  /// Extra shear from the slant setting (radians).
  final double slant;
  final double variation;

  /// Pen width relative to the x-height.
  final double penRatio;
  late final Map<String, List<GlyphVariant>> _table;

  bool get isEmpty => _table.isEmpty;

  List<GlyphVariant>? variants(String character) => _table[character];

  bool has(String character) => _table.containsKey(character);

  static GlyphVariant? makeVariant(GlyphInput input, HandwritingAnalysis analysis, double penRatio) {
    final scale = analysis.scaleCorrection * input.scale;
    final baseline = analysis.baselineCorrection;
    final offset = input.baselineOffset;

    List<Pt> place(Stroke path) => [for (final p in path) Pt(p.x * scale, (p.y - baseline) * scale + offset)];
    final strokes = input.strokes.map(place).toList();
    final outlines = input.outlines.map(place).toList();
    final allX = [for (final path in [...strokes, ...outlines]) for (final p in path) p.x];
    if (allX.isEmpty) return null;
    final minX = allX.reduce(math.min);
    final maxX = allX.reduce(math.max);

    final path = InkPath();
    for (var i = 0; i < strokes.length; i++) {
      final shifted = [for (final p in strokes[i]) Pt(p.x - minX, p.y)];
      final widths = [for (final p in input.strokes[i]) p.w * penRatio];
      StrokeOutline.add(shifted, widths, path);
    }

    // Pen-on-paper outlines keep their real thickness; a heavier pen setting
    // thickens them by tracing their edge.
    final thickening = math.max(0.0, penRatio - 0.15) * 0.9;
    for (final polygon in outlines) {
      if (polygon.length <= 2) continue;
      final shifted = StrokeOutline.smoothClosed([for (final p in polygon) Pt(p.x - minX, p.y)]);
      path.add(shifted);
      if (thickening > 0.005) {
        final ring = [...shifted, shifted[0]];
        StrokeOutline.add(ring, List.filled(ring.length, thickening), path);
      }
    }
    return GlyphVariant(path.polygons, math.max(maxX - minX, penRatio));
  }

  /// Umlauts and quotes that weren't written are built from other glyphs,
  /// so a missing "ä" still looks like the user's own "a".
  static void _addComposites(Map<String, List<GlyphVariant>> variants, double penRatio) {
    const umlauts = [('ä', 'a', -1.4), ('ö', 'o', -1.4), ('ü', 'u', -1.4), ('Ä', 'A', -2.15), ('Ö', 'O', -2.15), ('Ü', 'U', -2.15)];
    for (final (umlaut, base, dotY) in umlauts) {
      if (variants.containsKey(umlaut)) continue;
      final baseVariants = variants[base];
      if (baseVariants == null) continue;
      variants[umlaut] = [
        for (final variant in baseVariants)
          () {
            final path = InkPath()..polygons.addAll(variant.outline);
            final radius = penRatio * 0.75;
            StrokeOutline.addDot(Pt(variant.advance * 0.3, dotY), radius, path);
            StrokeOutline.addDot(Pt(variant.advance * 0.72, dotY), radius, path);
            return GlyphVariant(path.polygons, variant.advance);
          }(),
      ];
    }

    List<GlyphVariant> moved(List<GlyphVariant> list, double dy) => [
          for (final v in list) GlyphVariant([for (final poly in v.outline) [for (final p in poly) Pt(p.x, p.y + dy)]], v.advance),
        ];

    final straight = variants['"'];
    if (straight != null) {
      variants.putIfAbsent('“', () => straight);
      // Low quotes sit on the baseline.
      variants.putIfAbsent('„', () => moved(straight, 1.75));
    }
    final comma = variants[','];
    if (!variants.containsKey("'") && comma != null) variants["'"] = moved(comma, -1.6);
  }
}

/// Text in a system font for characters that haven't been written yet, so
/// nothing silently disappears. Shown visibly different on purpose.
///
/// The iPhone uses Noteworthy; Windows and Android have no such font, so these
/// pages use Helvetica-compatible metrics (Arial on screen, Helvetica in PDFs).
abstract final class FallbackFont {
  /// Helvetica's x-height (523 of 1000 units).
  static const _xHeightRatio = 0.523;

  /// Font size whose x-height equals [xHeight].
  static double size(double xHeight) => xHeight / _xHeightRatio;

  static double width(String text, double size) {
    var units = 0;
    for (final rune in text.runes) {
      units += _widths[rune] ?? 556;
    }
    return units / 1000 * size;
  }

  /// Helvetica advance widths (AFM, 1000 units per em).
  static final Map<int, int> _widths = () {
    const ascii = <int>[
      278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, // space … /
      556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, // 0 … ?
      1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, // @ … O
      667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, // P … _
      333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, // ` … o
      556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, // p … ~
    ];
    return {
      for (var i = 0; i < ascii.length; i++) 32 + i: ascii[i],
      'Ä'.codeUnitAt(0): 667, 'Ö'.codeUnitAt(0): 778, 'Ü'.codeUnitAt(0): 722,
      'ä'.codeUnitAt(0): 556, 'ö'.codeUnitAt(0): 556, 'ü'.codeUnitAt(0): 556, 'ß'.codeUnitAt(0): 611,
      '„'.codeUnitAt(0): 333, '“'.codeUnitAt(0): 333, '”'.codeUnitAt(0): 333,
      '‘'.codeUnitAt(0): 222, '’'.codeUnitAt(0): 222, '…'.codeUnitAt(0): 1000,
      '–'.codeUnitAt(0): 556, '—'.codeUnitAt(0): 1000, '•'.codeUnitAt(0): 350, '·'.codeUnitAt(0): 278,
    };
  }();
}
