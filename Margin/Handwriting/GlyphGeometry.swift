import CoreGraphics
import Foundation

/// A point of a normalised stroke. `w` scales the pen width at that point
/// (fast movement → thinner, slow → thicker), like real ink.
struct StrokePoint: Equatable, Sendable {
    var x: Float
    var y: Float
    var w: Float
}

typealias Stroke = [StrokePoint]

/// A raw touch sample from the capture canvas.
struct CapturedPoint: Equatable {
    var location: CGPoint
    var time: TimeInterval
}

/// Compact binary storage for glyph geometry (much smaller than JSON).
/// Layout: version byte, UInt16 path count, then per path a UInt16
/// point count followed by Float32 x, y, w for each point (little-endian).
///
/// Version 1: pen strokes written with a finger (centre lines with width).
/// Version 2: filled outlines traced from a scanned pen sample (closed
/// polygons, `w` unused; outer shapes and holes have opposite orientation).
enum GlyphStrokes {
    static func encode(_ strokes: [Stroke]) -> Data {
        encode(strokes, version: 1)
    }

    static func encodeOutlines(_ polygons: [Stroke]) -> Data {
        encode(polygons, version: 2)
    }

    private static func encode(_ strokes: [Stroke], version: UInt8) -> Data {
        var data = Data([version])
        let kept = strokes.prefix(Int(UInt16.max))
        append(UInt16(kept.count), to: &data)
        for stroke in kept {
            let points = stroke.prefix(Int(UInt16.max))
            append(UInt16(points.count), to: &data)
            for point in points {
                append(point.x.bitPattern, to: &data)
                append(point.y.bitPattern, to: &data)
                append(point.w.bitPattern, to: &data)
            }
        }
        return data
    }

    /// Finger strokes only (empty for outline glyphs).
    static func decode(_ data: Data) -> [Stroke] {
        data.first == 1 ? decodePaths(data) : []
    }

    /// Strokes and outlines, whichever the data contains.
    static func decodeGlyph(_ data: Data) -> (strokes: [Stroke], outlines: [Stroke]) {
        switch data.first {
        case 1?: (decodePaths(data), [])
        case 2?: ([], decodePaths(data))
        default: ([], [])
        }
    }

    private static func decodePaths(_ data: Data) -> [Stroke] {
        let bytes = [UInt8](data)
        guard let version = bytes.first, version == 1 || version == 2 else { return [] }
        var index = 1

        func read16() -> UInt16? {
            guard index + 2 <= bytes.count else { return nil }
            let value = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
            index += 2
            return value
        }

        func readFloat() -> Float? {
            guard index + 4 <= bytes.count else { return nil }
            var value: UInt32 = 0
            for offset in 0..<4 {
                value |= UInt32(bytes[index + offset]) << (8 * UInt32(offset))
            }
            index += 4
            return Float(bitPattern: value)
        }

        guard let strokeCount = read16() else { return [] }
        var strokes: [Stroke] = []
        for _ in 0..<strokeCount {
            guard let pointCount = read16() else { break }
            var stroke: Stroke = []
            stroke.reserveCapacity(Int(pointCount))
            for _ in 0..<pointCount {
                guard let x = readFloat(), let y = readFloat(), let w = readFloat() else { return strokes }
                stroke.append(StrokePoint(x: x, y: y, w: w))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}

/// Where the guide lines sit in a capture box. All capture boxes share these
/// proportions, so every sample is measured against the same x-height.
struct CaptureGuide: Equatable {
    var size: CGSize

    /// Distance between baseline and x-height line, in points.
    var xHeight: CGFloat { size.height * 0.2 }
    var baseline: CGFloat { size.height * 0.66 }
    var xLine: CGFloat { baseline - xHeight }
    var capLine: CGFloat { baseline - xHeight * 1.8 }
    var descenderLine: CGFloat { baseline + xHeight * 0.8 }
}

/// Bounds of normalised strokes.
struct GlyphBounds: Equatable {
    var minX: CGFloat
    var maxX: CGFloat
    var minY: CGFloat
    var maxY: CGFloat

    var width: CGFloat { maxX - minX }
    var height: CGFloat { maxY - minY }

    init(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    init?(_ strokes: [Stroke]) {
        let points = strokes.flatMap { $0 }
        guard let first = points.first else { return nil }
        var bounds = GlyphBounds(minX: CGFloat(first.x), maxX: CGFloat(first.x), minY: CGFloat(first.y), maxY: CGFloat(first.y))
        for point in points {
            bounds.minX = min(bounds.minX, CGFloat(point.x))
            bounds.maxX = max(bounds.maxX, CGFloat(point.x))
            bounds.minY = min(bounds.minY, CGFloat(point.y))
            bounds.maxY = max(bounds.maxY, CGFloat(point.y))
        }
        self = bounds
    }
}

/// Turns raw touches into normalised, simplified strokes.
enum GlyphProcessing {
    /// - Returns: strokes with baseline at y = 0, x-height line at y = −1 and
    ///   the leftmost ink at x = 0. Nil if nothing was written.
    static func normalize(_ raw: [[CapturedPoint]], guide: CaptureGuide) -> [Stroke]? {
        let strokes = raw.filter { !$0.isEmpty }
        guard !strokes.isEmpty, guide.xHeight > 0 else { return nil }
        let minX = strokes.flatMap { $0 }.map(\.location.x).min() ?? 0
        let unit = guide.xHeight

        return strokes.map { raw in
            // Steady the line: finger input is shakier than a pen.
            let stroke = stabilize(raw)
            let widths = penWidths(for: stroke)
            let points = zip(stroke, widths).map { point, width in
                StrokePoint(
                    x: Float((point.location.x - minX) / unit),
                    y: Float((point.location.y - guide.baseline) / unit),
                    w: Float(width)
                )
            }
            return simplify(points, tolerance: 0.012)
        }
    }

    /// Moving average over the touch positions (ends stay fixed), which removes
    /// the jitter of finger writing without rounding off real corners too much.
    static func stabilize(_ stroke: [CapturedPoint], radius: Int = 2) -> [CapturedPoint] {
        guard stroke.count > 2 * radius + 1 else { return stroke }
        var result = stroke
        for index in radius..<(stroke.count - radius) {
            var x: CGFloat = 0, y: CGFloat = 0
            for offset in -radius...radius {
                x += stroke[index + offset].location.x
                y += stroke[index + offset].location.y
            }
            let count = CGFloat(2 * radius + 1)
            result[index].location = CGPoint(x: x / count, y: y / count)
        }
        return result
    }

    /// Width factors from writing speed, smoothed, with a slight taper at the ends.
    static func penWidths(for stroke: [CapturedPoint]) -> [CGFloat] {
        guard stroke.count > 1 else { return [1.05] }
        var widths: [CGFloat] = [1.0]
        for index in 1..<stroke.count {
            let a = stroke[index - 1], b = stroke[index]
            let distance = hypot(b.location.x - a.location.x, b.location.y - a.location.y)
            let dt = max(b.time - a.time, 1.0 / 240.0)
            let speed = distance / CGFloat(dt) // points per second
            let factor = 1.14 - min(max((speed - 150) / 1900, 0), 1) * 0.42
            widths.append(factor)
        }
        // Moving average over 5 samples.
        var smoothed = widths
        for index in widths.indices {
            let window = widths[max(0, index - 2)...min(widths.count - 1, index + 2)]
            smoothed[index] = window.reduce(0, +) / CGFloat(window.count)
        }
        if smoothed.count > 3 {
            smoothed[0] *= 0.85
            smoothed[smoothed.count - 1] *= 0.8
        }
        return smoothed
    }

    /// Ramer–Douglas–Peucker simplification on x/y (keeps the width of kept points).
    static func simplify(_ points: Stroke, tolerance: Float) -> Stroke {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]

        while let range = stack.popLast() {
            let (start, end) = range
            guard end > start + 1 else { continue }
            let a = points[start], b = points[end]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max((dx * dx + dy * dy).squareRoot(), 1e-6)
            var maxDistance: Float = 0
            var maxIndex = start
            for index in (start + 1)..<end {
                let p = points[index]
                let distance = abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
                if distance > maxDistance {
                    maxDistance = distance
                    maxIndex = index
                }
            }
            if maxDistance > tolerance {
                keep[maxIndex] = true
                stack.append((start, maxIndex))
                stack.append((maxIndex, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}
