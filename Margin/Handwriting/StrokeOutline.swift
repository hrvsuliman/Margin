import CoreGraphics
import Foundation

fileprivate func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
fileprivate func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
fileprivate func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
fileprivate extension CGPoint {
    var length: CGFloat { hypot(x, y) }
    var normalized: CGPoint {
        let l = length
        return l > 1e-9 ? CGPoint(x: x / l, y: y / l) : CGPoint(x: 1, y: 0)
    }
}

/// Turns a centre line with varying width into a filled outline ("ink").
///
/// Every outline is built with the same orientation, so overlapping strokes
/// (loops in an "e", crossings in a "t") fill solidly with the non-zero rule.
/// Sharp corners are split into separate pieces with round ends, which avoids
/// spikes where the pen turns back on itself (like the top of an "n").
enum StrokeOutline {
    static func add(points rawPoints: [CGPoint], widths rawWidths: [CGFloat], to path: CGMutablePath) {
        guard !rawPoints.isEmpty, rawPoints.count == rawWidths.count else { return }

        // Drop repeated points.
        var points: [CGPoint] = [rawPoints[0]]
        var widths: [CGFloat] = [rawWidths[0]]
        for index in 1..<rawPoints.count where (rawPoints[index] - points[points.count - 1]).length > 0.01 {
            points.append(rawPoints[index])
            widths.append(rawWidths[index])
        }

        let maxWidth = widths.max() ?? 1
        let length = zip(points, points.dropFirst()).reduce(CGFloat(0)) { $0 + ($1.1 - $1.0).length }
        if points.count == 1 || length < maxWidth * 0.35 {
            addDot(center: points[0], radius: max(maxWidth * 0.6, 0.05), to: path)
            return
        }

        for piece in splitAtCorners(points, widths) {
            let (smoothPoints, smoothWidths) = chaikin(piece.0, piece.1)
            addBand(smoothPoints, smoothWidths, to: path)
        }
    }

    /// A filled circle with the same orientation as the bands.
    static func addDot(center: CGPoint, radius: CGFloat, to path: CGMutablePath) {
        let steps = 14
        for step in 0...steps {
            let angle = -2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
    }

    private static func splitAtCorners(_ points: [CGPoint], _ widths: [CGFloat]) -> [([CGPoint], [CGFloat])] {
        guard points.count > 2 else { return [(points, widths)] }
        var pieces: [([CGPoint], [CGFloat])] = []
        var start = 0
        for index in 1..<(points.count - 1) {
            let a = (points[index] - points[index - 1]).normalized
            let b = (points[index + 1] - points[index]).normalized
            let cosine = a.x * b.x + a.y * b.y
            if cosine < 0.34 { // turn sharper than ~70°
                pieces.append((Array(points[start...index]), Array(widths[start...index])))
                start = index
            }
        }
        pieces.append((Array(points[start...]), Array(widths[start...])))
        return pieces
    }

    /// One round of corner cutting for a smoother line.
    private static func chaikin(_ points: [CGPoint], _ widths: [CGFloat]) -> ([CGPoint], [CGFloat]) {
        guard points.count > 2 else { return (points, widths) }
        var outPoints: [CGPoint] = [points[0]]
        var outWidths: [CGFloat] = [widths[0]]
        for index in 0..<(points.count - 1) {
            let p = points[index], q = points[index + 1]
            let wp = widths[index], wq = widths[index + 1]
            outPoints.append(p * 0.75 + q * 0.25)
            outWidths.append(wp * 0.75 + wq * 0.25)
            outPoints.append(p * 0.25 + q * 0.75)
            outWidths.append(wp * 0.25 + wq * 0.75)
        }
        outPoints.append(points[points.count - 1])
        outWidths.append(widths[widths.count - 1])
        return (outPoints, outWidths)
    }

    private static func addBand(_ p: [CGPoint], _ w: [CGFloat], to path: CGMutablePath) {
        let n = p.count
        guard n >= 2 else {
            if let first = p.first { addDot(center: first, radius: (w.first ?? 1) / 2, to: path) }
            return
        }

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(n)
        right.reserveCapacity(n)
        for index in 0..<n {
            let tangent = (p[min(index + 1, n - 1)] - p[max(index - 1, 0)]).normalized
            let normal = CGPoint(x: -tangent.y, y: tangent.x)
            let radius = w[index] / 2
            left.append(p[index] + normal * radius)
            right.append(p[index] - normal * radius)
        }

        let endDirection = (p[n - 1] - p[n - 2]).normalized
        let startDirection = (p[1] - p[0]).normalized
        let capSteps = 6

        path.move(to: left[0])
        for point in left.dropFirst() { path.addLine(to: point) }

        // Round end: from the left side, around the tip, to the right side.
        let endNormalAngle = atan2(endDirection.x, -endDirection.y) // angle of (-d.y, d.x)
        let endRadius = w[n - 1] / 2
        for step in 1..<capSteps {
            let angle = endNormalAngle - CGFloat.pi * CGFloat(step) / CGFloat(capSteps)
            path.addLine(to: CGPoint(x: p[n - 1].x + cos(angle) * endRadius, y: p[n - 1].y + sin(angle) * endRadius))
        }

        for point in right.reversed() { path.addLine(to: point) }

        // Round start: from the right side, around the back, to the left side.
        let startNormalAngle = atan2(-startDirection.x, startDirection.y) // angle of (d.y, -d.x)
        let startRadius = w[0] / 2
        for step in 1..<capSteps {
            let angle = startNormalAngle - CGFloat.pi * CGFloat(step) / CGFloat(capSteps)
            path.addLine(to: CGPoint(x: p[0].x + cos(angle) * startRadius, y: p[0].y + sin(angle) * startRadius))
        }
        path.closeSubpath()
    }
}

/// Deterministic random numbers, so the same note always looks the same.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }

    /// −1 ... 1
    mutating func signed() -> CGFloat {
        unit() * 2 - 1
    }

    /// −1 ... 1, more often near 0 (sum of two).
    mutating func soft() -> CGFloat {
        (signed() + signed()) / 2
    }
}

/// Hashes that are stable across app launches (Swift's `hashValue` is not).
enum StableHash {
    static func of(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func combine(_ values: UInt64...) -> UInt64 {
        var generator = SeededRandom(seed: 0)
        var hash: UInt64 = 0x84222325
        for value in values {
            hash = (hash ^ value) &* 0x0000_0100_0000_01B3
            hash ^= generator.next()
        }
        return hash
    }
}
