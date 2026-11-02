import Foundation

/// Grades 1–6 (lower is better) or Oberstufe points 0–15 (higher is better).
enum GradeScale: String, CaseIterable, Identifiable, Codable, Sendable {
    case grades, points

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grades: "Noten 1–6"
        case .points: "Punkte 0–15"
        }
    }

    var range: ClosedRange<Double> { self == .grades ? 1...6 : 0...15 }
    var best: Double { self == .grades ? 1 : 15 }
    var worst: Double { self == .grades ? 6 : 0 }

    /// The usual values to pick from: 1, 1-, 2+, 2 … or 15 … 0 points.
    var options: [Double] {
        switch self {
        case .grades:
            [1.0, 1.3, 1.7, 2.0, 2.3, 2.7, 3.0, 3.3, 3.7, 4.0, 4.3, 4.7, 5.0, 5.3, 5.7, 6.0]
        case .points:
            (0...15).reversed().map(Double.init)
        }
    }

    func isBetter(_ a: Double, than b: Double) -> Bool {
        self == .grades ? a < b : a > b
    }

    /// "2-", "1+", "3" for grades; "11 P." for points.
    func label(_ value: Double) -> String {
        switch self {
        case .points:
            return "\(Int(value.rounded())) P."
        case .grades:
            let base = Int(value.rounded())
            let rest = value - Double(base)
            if rest > 0.15 { return "\(base)-" }
            if rest < -0.15 { return "\(base)+" }
            return "\(base)"
        }
    }

    /// Averages with two decimals, German style ("2,35").
    func average(_ value: Double) -> String {
        let text = String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
        return self == .points ? "\(text) P." : text
    }
}

struct GradeEntry: Equatable, Sendable {
    let value: Double
    let weight: Double
    let isWritten: Bool
}

enum GradeMath {
    static func weightedAverage(_ entries: [GradeEntry]) -> Double? {
        let total = entries.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        return entries.reduce(0) { $0 + $1.value * $1.weight } / total
    }

    /// The subject average: written and oral parts weighted by `writtenShare`.
    /// If one part has no grades yet, the other part counts alone.
    static func average(_ entries: [GradeEntry], writtenShare: Double) -> Double? {
        let written = weightedAverage(entries.filter(\.isWritten))
        let oral = weightedAverage(entries.filter { !$0.isWritten })
        switch (written, oral) {
        case let (w?, o?): return writtenShare * w + (1 - writtenShare) * o
        case let (w?, nil): return w
        case let (nil, o?): return o
        default: return nil
        }
    }

    /// The grade the next written exam (with `weight`) needs so the subject
    /// average reaches `target`: the worst grade on the scale that is still
    /// enough. Nil if even the best grade can't reach it.
    static func neededNext(
        _ entries: [GradeEntry], writtenShare: Double, target: Double, weight: Double = 1, scale: GradeScale
    ) -> Double? {
        let enough = scale.options.filter { option in
            guard let result = average(entries + [GradeEntry(value: option, weight: weight, isWritten: true)],
                                       writtenShare: writtenShare) else { return false }
            return scale == .grades ? result <= target + 1e-9 : result >= target - 1e-9
        }
        return enough.max { scale.isBetter($0, than: $1) }
    }
}
