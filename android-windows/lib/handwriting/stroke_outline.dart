// Turns a centre line with varying width into filled ink. Ported from StrokeOutline.swift.

import 'dart:math' as math;

import 'geometry.dart';

/// Every outline is built with the same orientation, so overlapping strokes
/// (loops in an "e", crossings in a "t") fill solidly with the non-zero rule.
/// Sharp corners are split into separate pieces with round ends, which avoids
/// spikes where the pen turns back on itself (like the top of an "n").
abstract final class StrokeOutline {
  static void add(List<Pt> rawPoints, List<double> rawWidths, InkPath path) {
    if (rawPoints.isEmpty || rawPoints.length != rawWidths.length) return;

    // Drop repeated points.
    final points = <Pt>[rawPoints[0]];
    final widths = <double>[rawWidths[0]];
    for (var i = 1; i < rawPoints.length; i++) {
      if ((rawPoints[i] - points.last).length > 0.01) {
        points.add(rawPoints[i]);
        widths.add(rawWidths[i]);
      }
    }

    final maxWidth = widths.reduce(math.max);
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).length;
    }
    if (points.length == 1 || length < maxWidth * 0.35) {
      addDot(points[0], math.max(maxWidth * 0.6, 0.05), path);
      return;
    }

    for (final piece in _splitAtCorners(points, widths)) {
      final smooth = _chaikin(piece.$1, piece.$2);
      _addBand(smooth.$1, smooth.$2, path);
    }
  }

  /// One round of corner cutting on a closed polygon (keeps its orientation).
  static List<Pt> smoothClosed(List<Pt> points) {
    if (points.length <= 3) return points;
    final result = <Pt>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final q = points[(i + 1) % points.length];
      result.add(p * 0.75 + q * 0.25);
      result.add(p * 0.25 + q * 0.75);
    }
    return result;
  }

  /// Signed area (negative = same orientation as the stroke outlines).
  static double signedArea(List<Pt> points) {
    if (points.length <= 2) return 0;
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final q = points[(i + 1) % points.length];
      area += p.x * q.y - q.x * p.y;
    }
    return area / 2;
  }

  /// A filled circle with the same orientation as the bands.
  static void addDot(Pt center, double radius, InkPath path) {
    const steps = 14;
    path.add([
      for (var step = 0; step <= steps; step++)
        Pt(
          center.x + math.cos(-2 * math.pi * step / steps) * radius,
          center.y + math.sin(-2 * math.pi * step / steps) * radius,
        ),
    ]);
  }

  static List<(List<Pt>, List<double>)> _splitAtCorners(List<Pt> points, List<double> widths) {
    if (points.length <= 2) return [(points, widths)];
    final pieces = <(List<Pt>, List<double>)>[];
    var start = 0;
    for (var i = 1; i < points.length - 1; i++) {
      final a = (points[i] - points[i - 1]).normalized;
      final b = (points[i + 1] - points[i]).normalized;
      final cosine = a.x * b.x + a.y * b.y;
      if (cosine < 0.34) {
        // turn sharper than ~70°
        pieces.add((points.sublist(start, i + 1), widths.sublist(start, i + 1)));
        start = i;
      }
    }
    pieces.add((points.sublist(start), widths.sublist(start)));
    return pieces;
  }

  /// One round of corner cutting for a smoother line.
  static (List<Pt>, List<double>) _chaikin(List<Pt> points, List<double> widths) {
    if (points.length <= 2) return (points, widths);
    final outPoints = <Pt>[points[0]];
    final outWidths = <double>[widths[0]];
    for (var i = 0; i < points.length - 1; i++) {
      final p = points[i], q = points[i + 1];
      final wp = widths[i], wq = widths[i + 1];
      outPoints.add(p * 0.75 + q * 0.25);
      outWidths.add(wp * 0.75 + wq * 0.25);
      outPoints.add(p * 0.25 + q * 0.75);
      outWidths.add(wp * 0.25 + wq * 0.75);
    }
    outPoints.add(points.last);
    outWidths.add(widths.last);
    return (outPoints, outWidths);
  }

  static void _addBand(List<Pt> p, List<double> w, InkPath path) {
    final n = p.length;
    if (n < 2) {
      if (p.isNotEmpty) addDot(p.first, (w.isEmpty ? 1 : w.first) / 2, path);
      return;
    }

    final left = <Pt>[];
    final right = <Pt>[];
    for (var i = 0; i < n; i++) {
      final tangent = (p[math.min(i + 1, n - 1)] - p[math.max(i - 1, 0)]).normalized;
      final normal = Pt(-tangent.y, tangent.x);
      final radius = w[i] / 2;
      left.add(p[i] + normal * radius);
      right.add(p[i] - normal * radius);
    }

    final endDirection = (p[n - 1] - p[n - 2]).normalized;
    final startDirection = (p[1] - p[0]).normalized;
    const capSteps = 6;
    final polygon = <Pt>[...left];

    // Round end: from the left side, around the tip, to the right side.
    final endNormalAngle = math.atan2(endDirection.x, -endDirection.y);
    final endRadius = w[n - 1] / 2;
    for (var step = 1; step < capSteps; step++) {
      final angle = endNormalAngle - math.pi * step / capSteps;
      polygon.add(Pt(p[n - 1].x + math.cos(angle) * endRadius, p[n - 1].y + math.sin(angle) * endRadius));
    }

    polygon.addAll(right.reversed);

    // Round start: from the right side, around the back, to the left side.
    final startNormalAngle = math.atan2(-startDirection.x, startDirection.y);
    final startRadius = w[0] / 2;
    for (var step = 1; step < capSteps; step++) {
      final angle = startNormalAngle - math.pi * step / capSteps;
      polygon.add(Pt(p[0].x + math.cos(angle) * startRadius, p[0].y + math.sin(angle) * startRadius));
    }
    path.add(polygon);
  }
}
