import CoreGraphics
import Foundation

/// One written sample, decoded and detached from the database (safe to use off the main thread).
struct GlyphInput: Sendable, Equatable {
    var uid: UUID
    var strokes: [Stroke]
    var scale: Double
    var baselineOffset: Double
}

/// Everything needed to build a `HandwritingFont`, as plain values.
struct FontSource: Sendable {
    var glyphs: [String: [GlyphInput]] = [:]
    var letterSpacing: Double = 0.14
    var wordSpacing: Double = 0.75
    var slantAdjust: Double = 0
    var variation: Double = 1

    static let empty = FontSource()

    @MainActor
    init(profile: HandwritingProfile) {
        var glyphs: [String: [GlyphInput]] = [:]
        for sample in (profile.glyphs ?? []).sorted(by: { $0.createdAt < $1.createdAt }) {
            let strokes = GlyphStrokes.decode(sample.strokeData)
            guard !strokes.isEmpty else { continue }
            glyphs[sample.character, default: []].append(
                GlyphInput(uid: sample.uid, strokes: strokes, scale: sample.scale, baselineOffset: sample.baselineOffset)
            )
        }
        self.glyphs = glyphs
        letterSpacing = profile.letterSpacing
        wordSpacing = profile.wordSpacing
        slantAdjust = profile.slantAdjust
        variation = profile.variation
    }

    init() {}
}

/// What the app learns from the samples: how big and where the user actually
/// wrote compared to the guide lines, the natural slant, and which characters
/// stand out. Size and baseline corrections are applied automatically when rendering.
struct HandwritingAnalysis: Sendable {
    struct Outlier: Sendable, Identifiable {
        var id: UUID { glyphUID }
        let character: String
        let glyphUID: UUID
        /// Height compared to similar characters (1 = typical).
        let ratio: Double
        /// Scale that would bring it in line.
        let suggestedScale: Double
    }

    var captured: Int = 0
    var total: Int = HandwritingCharset.all.count
    var missing: [String] = HandwritingCharset.all
    var variantCount: Int = 0
    /// Multiply raw sample coordinates by this so x-height letters are exactly 1 high.
    var scaleCorrection: Double = 1
    /// Raw y of the median baseline (subtract before scaling).
    var baselineCorrection: Double = 0
    /// Natural slant of the samples in degrees (positive leans right).
    var slantDegrees: Double = 0
    /// How evenly sized the x-height letters are (0 = very uneven … 1 = perfectly even).
    var consistency: Double = 1
    var outliers: [Outlier] = []

    static func analyze(_ glyphs: [String: [GlyphInput]]) -> HandwritingAnalysis {
        var result = HandwritingAnalysis()
        result.captured = HandwritingCharset.all.filter { glyphs[$0]?.isEmpty == false }.count
        result.missing = HandwritingCharset.all.filter { glyphs[$0]?.isEmpty != false }
        result.variantCount = glyphs.values.reduce(0) { $0 + $1.count }

        // Baseline: where the ink of baseline characters ends.
        let bottoms = glyphs.filter { HandwritingCharset.baselineCharacters.contains($0.key) }
            .flatMap { $0.value }
            .compactMap { GlyphBounds($0.strokes)?.maxY }
        if let bottom = median(bottoms.map { Double($0) }) {
            result.baselineCorrection = min(max(bottom, -0.5), 0.5)
        }

        // Size: how tall x-height letters really are.
        let xTops = topRatios(glyphs, characters: HandwritingCharset.xHeightLetters, baseline: result.baselineCorrection)
        if let medianTop = median(xTops.map(\.top)), medianTop > 0.1 {
            result.scaleCorrection = min(max(1 / medianTop, 0.6), 1.7)
            let deviations = xTops.map { abs($0.top / medianTop - 1) }
            result.consistency = max(0, 1 - (median(deviations) ?? 0) * 3)
            result.outliers += xTops.compactMap { entry -> Outlier? in
                let ratio = entry.top / medianTop
                guard ratio < 0.72 || ratio > 1.35 else { return nil }
                return Outlier(character: entry.character, glyphUID: entry.uid, ratio: ratio,
                               suggestedScale: entry.scale / ratio)
            }
        }

        let capTops = topRatios(glyphs, characters: HandwritingCharset.capitalLetters, baseline: result.baselineCorrection)
        if let medianCap = median(capTops.map(\.top)), medianCap > 0.1 {
            result.outliers += capTops.compactMap { entry -> Outlier? in
                let ratio = entry.top / medianCap
                guard ratio < 0.72 || ratio > 1.35 else { return nil }
                return Outlier(character: entry.character, glyphUID: entry.uid, ratio: ratio,
                               suggestedScale: entry.scale / ratio)
            }
        }

        result.slantDegrees = slant(of: glyphs)
        return result
    }

    private struct TopEntry {
        let character: String
        let uid: UUID
        let top: Double
        let scale: Double
    }

    /// Height above the baseline for each sample of the given characters, including manual scale.
    private static func topRatios(_ glyphs: [String: [GlyphInput]], characters: Set<String>, baseline: Double) -> [TopEntry] {
        var entries: [TopEntry] = []
        for (character, inputs) in glyphs where characters.contains(character) {
            for input in inputs {
                guard let bounds = GlyphBounds(input.strokes) else { continue }
                let top = (baseline - Double(bounds.minY)) * input.scale
                entries.append(TopEntry(character: character, uid: input.uid, top: top, scale: input.scale))
            }
        }
        return entries
    }

    /// Average lean of mostly vertical stroke segments.
    private static func slant(of glyphs: [String: [GlyphInput]]) -> Double {
        var weighted = 0.0
        var totalLength = 0.0
        for input in glyphs.values.flatMap({ $0 }) {
            for stroke in input.strokes where stroke.count > 1 {
                for (a, b) in zip(stroke, stroke.dropFirst()) {
                    var dx = Double(b.x - a.x)
                    var dy = Double(b.y - a.y)
                    let length = (dx * dx + dy * dy).squareRoot()
                    guard length > 0.05, abs(dy) > 2 * abs(dx) else { continue }
                    if dy > 0 { dx = -dx; dy = -dy } // always measure upwards
                    weighted += atan2(dx, -dy) * length
                    totalLength += length
                }
            }
        }
        guard totalLength > 0 else { return 0 }
        return weighted / totalLength * 180 / .pi
    }

    /// Letter gap measured from the sample word, in x-heights. Nil if a letter
    /// of the word hasn't been written yet.
    static func letterSpacing(word: String, written: [Stroke], glyphs: [String: [GlyphInput]]) -> Double? {
        let analysis = analyze(glyphs)
        guard let wordBounds = GlyphBounds(written) else { return nil }
        let letters = word.map { String($0) }
        guard letters.count > 1 else { return nil }
        var glyphWidths = 0.0
        for letter in letters {
            guard let input = glyphs[letter]?.first, let bounds = GlyphBounds(input.strokes) else { return nil }
            glyphWidths += Double(bounds.width) * input.scale
        }
        let wordWidth = Double(wordBounds.width)
        let gap = (wordWidth - glyphWidths) / Double(letters.count - 1) * analysis.scaleCorrection
        return min(max(gap, 0.02), 0.9)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
