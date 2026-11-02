import CoreGraphics
import CoreText
import Foundation

/// The user's handwriting, ready to draw: every written sample becomes a filled
/// outline in x-height units (baseline at y = 0, x-height at y = −1).
/// Built from a `FontSource` off the main thread; immutable afterwards.
final class HandwritingFont: @unchecked Sendable {
    struct Variant {
        let outline: CGPath
        /// Ink width in x-heights.
        let advance: CGFloat
    }

    let analysis: HandwritingAnalysis
    let letterSpacing: CGFloat
    let wordSpacing: CGFloat
    /// Extra shear from the slant setting (radians).
    let slant: CGFloat
    let variation: CGFloat
    /// Pen width relative to the x-height.
    let penRatio: CGFloat
    private let table: [Character: [Variant]]

    var isEmpty: Bool { table.isEmpty }

    init(source: FontSource, penRatio: CGFloat) {
        let analysis = HandwritingAnalysis.analyze(source.glyphs)
        self.analysis = analysis
        self.penRatio = penRatio
        letterSpacing = CGFloat(source.letterSpacing)
        wordSpacing = CGFloat(source.wordSpacing)
        slant = CGFloat(source.slantAdjust) * .pi / 180
        variation = CGFloat(source.variation)

        var built: [Character: [Variant]] = [:]
        for (key, inputs) in source.glyphs {
            guard let character = key.first, key.count == 1 else { continue }
            let list = inputs.compactMap { Self.makeVariant($0, analysis: analysis, penRatio: penRatio) }
            if !list.isEmpty { built[character] = list }
        }
        Self.addComposites(to: &built, penRatio: penRatio)
        table = built
    }

    func variants(for character: Character) -> [Variant]? {
        table[character]
    }

    func has(_ character: Character) -> Bool {
        table[character] != nil
    }

    // MARK: Building

    static func makeVariant(_ input: GlyphInput, analysis: HandwritingAnalysis, penRatio: CGFloat) -> Variant? {
        let scale = CGFloat(analysis.scaleCorrection * input.scale)
        let baseline = CGFloat(analysis.baselineCorrection)
        let offset = CGFloat(input.baselineOffset)

        func place(_ path: Stroke) -> [CGPoint] {
            path.map { point in
                CGPoint(x: CGFloat(point.x) * scale, y: (CGFloat(point.y) - baseline) * scale + offset)
            }
        }
        let strokes = input.strokes.map(place)
        let outlines = input.outlines.map(place)
        let allX = (strokes + outlines).flatMap { $0 }.map(\.x)
        guard let minX = allX.min(), let maxX = allX.max() else { return nil }

        let path = CGMutablePath()
        for (stroke, raw) in zip(strokes, input.strokes) {
            let shifted = stroke.map { CGPoint(x: $0.x - minX, y: $0.y) }
            let widths = raw.map { CGFloat($0.w) * penRatio }
            StrokeOutline.add(points: shifted, widths: widths, to: path)
        }

        // Pen-on-paper outlines keep their real thickness; a heavier pen setting
        // thickens them by tracing their edge.
        let thickening = max(0, penRatio - 0.15) * 0.9
        for polygon in outlines where polygon.count > 2 {
            let shifted = StrokeOutline.smoothClosed(polygon.map { CGPoint(x: $0.x - minX, y: $0.y) })
            path.move(to: shifted[0])
            for point in shifted.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            if thickening > 0.005 {
                let ring = shifted + [shifted[0]]
                StrokeOutline.add(points: ring, widths: Array(repeating: thickening, count: ring.count), to: path)
            }
        }
        return Variant(outline: path.copy() ?? path, advance: max(maxX - minX, penRatio))
    }

    /// Umlauts and quotes that weren't written are built from other glyphs,
    /// so a missing "ä" still looks like the user's own "a".
    private static func addComposites(to variants: inout [Character: [Variant]], penRatio: CGFloat) {
        let umlauts: [(Character, Character, CGFloat)] = [
            ("ä", "a", -1.4), ("ö", "o", -1.4), ("ü", "u", -1.4),
            ("Ä", "A", -2.15), ("Ö", "O", -2.15), ("Ü", "U", -2.15),
        ]
        for (umlaut, base, dotY) in umlauts where variants[umlaut] == nil {
            guard let baseVariants = variants[base] else { continue }
            variants[umlaut] = baseVariants.map { variant in
                let path = CGMutablePath()
                path.addPath(variant.outline)
                let radius = penRatio * 0.75
                StrokeOutline.addDot(center: CGPoint(x: variant.advance * 0.3, y: dotY), radius: radius, to: path)
                StrokeOutline.addDot(center: CGPoint(x: variant.advance * 0.72, y: dotY), radius: radius, to: path)
                return Variant(outline: path.copy() ?? path, advance: variant.advance)
            }
        }

        if let straight = variants["\""] {
            if variants["“"] == nil { variants["“"] = straight }
            if variants["„"] == nil {
                // Low quotes sit on the baseline.
                variants["„"] = straight.map { variant in
                    let path = CGMutablePath()
                    path.addPath(variant.outline, transform: CGAffineTransform(translationX: 0, y: 1.75))
                    return Variant(outline: path.copy() ?? path, advance: variant.advance)
                }
            }
        }
        if variants["'"] == nil, let comma = variants[","] {
            variants["'"] = comma.map { variant in
                let path = CGMutablePath()
                path.addPath(variant.outline, transform: CGAffineTransform(translationX: 0, y: -1.6))
                return Variant(outline: path.copy() ?? path, advance: variant.advance)
            }
        }
    }
}

/// A system font used for characters that haven't been written yet,
/// so nothing silently disappears. Shown visibly different on purpose.
enum FallbackFont {
    static let name = "Noteworthy-Light"

    /// Font size whose x-height equals `xHeight`.
    static func size(forXHeight xHeight: CGFloat) -> CGFloat {
        xHeight / ratio
    }

    private static let ratio: CGFloat = {
        let reference = CTFontCreateWithName(name as CFString, 100, nil)
        let xHeight = CTFontGetXHeight(reference)
        return xHeight > 1 ? xHeight / 100 : 0.48
    }()

    static func width(of text: String, size: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
