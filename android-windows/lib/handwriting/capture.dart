// Turns pen (or finger) input into stored glyph strokes. Ported from
// GlyphProcessing and CaptureGuide in GlyphGeometry.swift. On a pen PC the
// pen's pressure is used as well, on top of the iPhone's speed-based width.

import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';

/// A raw pen sample from the capture canvas.
class CapturedPoint {
  const CapturedPoint(this.x, this.y, this.time, [this.pressure]);
  final double x;
  final double y;

  /// Seconds.
  final double time;

  /// 0 … 1 when the device reports pen pressure, otherwise null.
  final double? pressure;
}

/// Where the guide lines sit in a capture box. All capture boxes share these
/// proportions, so every sample is measured against the same x-height.
class CaptureGuide {
  const CaptureGuide(this.width, this.height);
  final double width;
  final double height;

  /// Distance between baseline and x-height line.
  double get xHeight => height * 0.2;
  double get baseline => height * 0.66;
  double get xLine => baseline - xHeight;
  double get capLine => baseline - xHeight * 1.8;
  double get descenderLine => baseline + xHeight * 0.8;
}

abstract final class GlyphProcessing {
  /// Strokes with baseline at y = 0, x-height line at y = −1 and the leftmost
  /// ink at x = 0. Null if nothing was written.
  static List<Stroke>? normalize(List<List<CapturedPoint>> raw, CaptureGuide guide) {
    final strokes = raw.where((s) => s.isNotEmpty).toList();
    if (strokes.isEmpty || guide.xHeight <= 0) return null;
    final minX = strokes.expand((s) => s).map((p) => p.x).reduce(math.min);
    final unit = guide.xHeight;

    return [
      for (final rawStroke in strokes)
        () {
          // Steady the line (helps most with finger input).
          final stroke = stabilize(rawStroke);
          final widths = penWidths(stroke);
          final points = [
            for (var i = 0; i < stroke.length; i++)
              StrokePoint(
                _f32((stroke[i].x - minX) / unit),
                _f32((stroke[i].y - guide.baseline) / unit),
                _f32(widths[i]),
              ),
          ];
          return simplify(points, 0.012);
        }(),
    ];
  }

  /// Rounded to Float32 like the stored format, so what is shown equals what is saved.
  static double _f32(double v) {
    _scratch[0] = v;
    return _scratch[0];
  }

  static final _scratch = Float32List(1);

  /// Moving average over the positions (ends stay fixed), which removes jitter
  /// without rounding off real corners too much.
  static List<CapturedPoint> stabilize(List<CapturedPoint> stroke, {int radius = 2}) {
    if (stroke.length <= 2 * radius + 1) return stroke;
    final result = [...stroke];
    for (var i = radius; i < stroke.length - radius; i++) {
      var x = 0.0, y = 0.0;
      for (var o = -radius; o <= radius; o++) {
        x += stroke[i + o].x;
        y += stroke[i + o].y;
      }
      final count = 2 * radius + 1;
      result[i] = CapturedPoint(x / count, y / count, stroke[i].time, stroke[i].pressure);
    }
    return result;
  }

  /// Width factors from writing speed (and pen pressure, when known), smoothed,
  /// with a slight taper at the ends.
  static List<double> penWidths(List<CapturedPoint> stroke) {
    if (stroke.length <= 1) return [1.05];
    final widths = <double>[1.0];
    for (var i = 1; i < stroke.length; i++) {
      final a = stroke[i - 1], b = stroke[i];
      final distance = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
      final dt = math.max(b.time - a.time, 1.0 / 240.0);
      final speed = distance / dt; // points per second
      widths.add(1.14 - ((speed - 150) / 1900).clamp(0.0, 1.0) * 0.42);
    }
    // A real pen: harder pressure → wider line (average pressure keeps the width).
    final pressures = [for (final p in stroke) p.pressure];
    if (pressures.every((p) => p != null)) {
      final values = pressures.cast<double>();
      final spread = values.reduce(math.max) - values.reduce(math.min);
      if (spread > 0.02) {
        final mean = values.reduce((a, b) => a + b) / values.length;
        for (var i = 0; i < widths.length; i++) {
          widths[i] *= (1 + (values[i] - mean) * 0.8).clamp(0.6, 1.4);
        }
      }
    }
    // Moving average over 5 samples.
    final smoothed = [...widths];
    for (var i = 0; i < widths.length; i++) {
      final window = widths.sublist(math.max(0, i - 2), math.min(widths.length, i + 3));
      smoothed[i] = window.reduce((a, b) => a + b) / window.length;
    }
    if (smoothed.length > 3) {
      smoothed[0] *= 0.85;
      smoothed[smoothed.length - 1] *= 0.8;
    }
    return smoothed;
  }

  /// Ramer–Douglas–Peucker simplification on x/y (keeps the width of kept points).
  static Stroke simplify(Stroke points, double tolerance) {
    if (points.length <= 2) return points;
    final keep = List.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    final stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (start, end) = stack.removeLast();
      if (end <= start + 1) continue;
      final a = points[start], b = points[end];
      final dx = b.x - a.x, dy = b.y - a.y;
      final length = math.max(math.sqrt(dx * dx + dy * dy), 1e-6);
      var maxDistance = 0.0;
      var maxIndex = start;
      for (var i = start + 1; i < end; i++) {
        final p = points[i];
        final distance = (dy * p.x - dx * p.y + b.x * a.y - b.y * a.x).abs() / length;
        if (distance > maxDistance) {
          maxDistance = distance;
          maxIndex = i;
        }
      }
      if (maxDistance > tolerance) {
        keep[maxIndex] = true;
        stack.add((start, maxIndex));
        stack.add((maxIndex, end));
      }
    }
    return [for (var i = 0; i < points.length; i++) if (keep[i]) points[i]];
  }
}
