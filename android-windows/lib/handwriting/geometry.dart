// Points, the glyph storage format, and the deterministic random numbers of the
// handwriting engine. Ported from GlyphGeometry.swift and StrokeOutline.swift.
//
// The random numbers and hashes use 64-bit wrapping integer arithmetic exactly
// like the Swift code, so a note looks the same on the iPhone, Android and Windows.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// A point in glyph units or page points (y points down).
class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);

  double get length => math.sqrt(x * x + y * y);

  Pt get normalized {
    final l = length;
    return l > 1e-9 ? Pt(x / l, y / l) : const Pt(1, 0);
  }

  @override
  String toString() => 'Pt(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// One closed polygon of ink.
typedef Polygon = List<Pt>;

/// Filled ink: closed polygons that are filled together with the non-zero rule
/// (like a CGPath made only of closed subpaths).
class InkPath {
  final List<Polygon> polygons = [];

  bool get isEmpty => polygons.isEmpty;

  void add(Polygon polygon) {
    if (polygon.length > 2) polygons.add(polygon);
  }

  /// Adds other polygons, each point mapped through [transform].
  void addAll(Iterable<Polygon> others, Pt Function(Pt) transform) {
    for (final polygon in others) {
      polygons.add([for (final p in polygon) transform(p)]);
    }
  }

  int get pointCount => polygons.fold(0, (sum, p) => sum + p.length);
}

/// A point of a stored glyph path. `w` scales the pen width at that point.
class StrokePoint {
  const StrokePoint(this.x, this.y, this.w);
  final double x;
  final double y;
  final double w;
}

typedef Stroke = List<StrokePoint>;

/// The binary glyph format of the iPhone app (`GlyphStrokes`):
/// version byte, UInt16 path count, then per path a UInt16 point count followed
/// by Float32 x, y, w for each point, all little-endian.
///
/// Version 1: finger strokes (centre lines with width).
/// Version 2: filled outlines traced from a pen sample on paper.
abstract final class GlyphStrokes {
  static Uint8List encode(List<Stroke> strokes, {int version = 1}) {
    final kept = strokes.take(0xFFFF).toList();
    final size = 3 + kept.fold<int>(0, (sum, s) => sum + 2 + 12 * math.min(s.length, 0xFFFF));
    final data = ByteData(size);
    var index = 0;
    data.setUint8(index++, version);
    data.setUint16(index, kept.length, Endian.little);
    index += 2;
    for (final stroke in kept) {
      final points = stroke.take(0xFFFF).toList();
      data.setUint16(index, points.length, Endian.little);
      index += 2;
      for (final p in points) {
        data.setFloat32(index, p.x, Endian.little);
        data.setFloat32(index + 4, p.y, Endian.little);
        data.setFloat32(index + 8, p.w, Endian.little);
        index += 12;
      }
    }
    return data.buffer.asUint8List();
  }

  static Uint8List encodeOutlines(List<Stroke> polygons) => encode(polygons, version: 2);

  /// Strokes and outlines, whichever the data contains.
  static ({List<Stroke> strokes, List<Stroke> outlines}) decodeGlyph(Uint8List bytes) {
    if (bytes.isEmpty) return (strokes: const [], outlines: const []);
    return switch (bytes[0]) {
      1 => (strokes: _decodePaths(bytes), outlines: const []),
      2 => (strokes: const [], outlines: _decodePaths(bytes)),
      _ => (strokes: const [], outlines: const []),
    };
  }

  /// Glyph data as it appears in an iPhone backup (Swift encodes `Data` as base64).
  static ({List<Stroke> strokes, List<Stroke> outlines}) decodeBase64(String value) {
    try {
      return decodeGlyph(base64Decode(value));
    } on FormatException {
      return (strokes: const [], outlines: const []);
    }
  }

  static List<Stroke> _decodePaths(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var index = 1;
    int? read16() {
      if (index + 2 > bytes.length) return null;
      final value = data.getUint16(index, Endian.little);
      index += 2;
      return value;
    }

    double? readFloat() {
      if (index + 4 > bytes.length) return null;
      final value = data.getFloat32(index, Endian.little);
      index += 4;
      return value;
    }

    final count = read16();
    if (count == null) return [];
    final strokes = <Stroke>[];
    for (var s = 0; s < count; s++) {
      final pointCount = read16();
      if (pointCount == null) break;
      final stroke = <StrokePoint>[];
      for (var i = 0; i < pointCount; i++) {
        final x = readFloat(), y = readFloat(), w = readFloat();
        if (x == null || y == null || w == null) return strokes;
        stroke.add(StrokePoint(x, y, w));
      }
      strokes.add(stroke);
    }
    return strokes;
  }
}

/// Bounds of glyph paths.
class GlyphBounds {
  const GlyphBounds(this.minX, this.maxX, this.minY, this.maxY);
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;

  static GlyphBounds? of(Iterable<Stroke> strokes) {
    double? minX, maxX, minY, maxY;
    for (final stroke in strokes) {
      for (final p in stroke) {
        minX = minX == null ? p.x : math.min(minX, p.x);
        maxX = maxX == null ? p.x : math.max(maxX, p.x);
        minY = minY == null ? p.y : math.min(minY, p.y);
        maxY = maxY == null ? p.y : math.max(maxY, p.y);
      }
    }
    if (minX == null) return null;
    return GlyphBounds(minX, maxX!, minY!, maxY!);
  }
}

/// Deterministic random numbers (SplitMix64), so the same note always looks the same.
class SeededRandom {
  SeededRandom(int seed) : _state = seed + _golden;

  static const _golden = 0x9E3779B97F4A7C15;
  int _state;

  /// A 64-bit value (as Dart's signed int; use [unsignedMod] for ranges).
  int next() {
    _state += _golden;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// 0 ..< 1
  double unit() => (next() >>> 11) / 9007199254740992.0;

  /// −1 ... 1
  double signed() => unit() * 2 - 1;

  /// −1 ... 1, more often near 0 (sum of two).
  double soft() => (signed() + signed()) / 2;
}

/// `value % n` with [value] read as an unsigned 64-bit number (Swift's `UInt64 % n`).
int unsignedMod(int value, int n) => (((value >>> 1) % n) * 2 + (value & 1)) % n;

/// Hashes that are the same on every device and every launch.
abstract final class StableHash {
  /// FNV-1a over the UTF-8 bytes.
  static int of(String string) {
    var hash = 0xCBF29CE484222325;
    for (final byte in utf8.encode(string)) {
      hash ^= byte;
      hash *= 0x00000100000001B3;
    }
    return hash;
  }

  static int combine(List<int> values) {
    final generator = SeededRandom(0);
    var hash = 0x84222325;
    for (final value in values) {
      hash = (hash ^ value) * 0x00000100000001B3;
      hash ^= generator.next();
    }
    return hash;
  }
}
