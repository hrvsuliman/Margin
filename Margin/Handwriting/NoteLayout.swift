import CoreGraphics
import Foundation
import ImageIO

/// Paper and pen settings, in PDF points (1 pt = 1/72 inch).
struct PageSettings: Equatable, Sendable {
    static let a4 = CGSize(width: 595.28, height: 841.89)

    var pageSize: CGSize = PageSettings.a4
    var paper: PaperStyle = .lined
    var lineSpacing: CGFloat = PageSettings.mm(8)
    var writingSize: CGFloat = 1
    var penColor: PenColor = .royalBlue
    var penWeight: CGFloat = 1
    var marginTop: CGFloat = PageSettings.mm(20)
    var marginBottom: CGFloat = PageSettings.mm(15)
    var marginLeft: CGFloat = PageSettings.mm(15)
    var marginRight: CGFloat = PageSettings.mm(25)
    var showMarginLine = true
    var showPageNumbers = true
    var showHeader = true
    var printPaper = true

    static func mm(_ millimetres: Double) -> CGFloat {
        CGFloat(millimetres * 72 / 25.4)
    }

    /// Height of a lowercase "x" in points.
    var xHeight: CGFloat { lineSpacing * 0.34 * writingSize }
    /// Pen width relative to the x-height.
    var penRatio: CGFloat { 0.15 * penWeight }
    var contentWidth: CGFloat { pageSize.width - marginLeft - marginRight }
    var linesPerPage: Int { max(1, Int((pageSize.height - marginTop - marginBottom) / lineSpacing)) }

    @MainActor
    init(document: NoteDocument) {
        paper = document.paper
        lineSpacing = Self.mm(document.lineSpacingMM)
        writingSize = CGFloat(document.writingSize)
        penColor = document.penColor
        penWeight = CGFloat(document.penWeight)
        marginTop = Self.mm(document.marginTopMM)
        marginBottom = Self.mm(document.marginBottomMM)
        marginLeft = Self.mm(document.marginLeftMM)
        marginRight = Self.mm(document.marginRightMM)
        showMarginLine = document.showMarginLine
        showPageNumbers = document.showPageNumbers
        showHeader = document.showHeader
        printPaper = document.printPaper
    }

    init() {}
}

/// The text of a note, as plain values.
struct NoteContent: Equatable, Sendable {
    var title: String
    /// Small line at the top right of page 1, e.g. "Mathematik · 02.11.2026".
    var header: String
    var body: String
    var seed: UInt64
    /// Pictures referenced by `[[Bild:<uid>]]` lines.
    var images: [UUID: NoteImageRef] = [:]
}

/// Where a note picture's file is and how big it should be.
struct NoteImageRef: Equatable, Sendable {
    let url: URL
    let heightLines: Int
    let caption: String
}

/// A structural line of the note source.
enum NoteBlock: Equatable {
    case heading(String)
    case subheading(String)
    case bullet(String)
    case paragraph(String)
    case image(UUID)
    case blank

    static let imagePrefix = "[[Bild:"

    static func imageLine(_ id: UUID) -> String { "\(imagePrefix)\(id.uuidString)]]" }

    /// "# " heading, "## " subheading, "- " / "• " / "* " list item, empty line = blank.
    static func parse(_ text: String) -> [NoteBlock] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { return .blank }
                if line.hasPrefix(imagePrefix), line.hasSuffix("]]"),
                   let id = UUID(uuidString: String(line.dropFirst(imagePrefix.count).dropLast(2))) {
                    return .image(id)
                }
                if line.hasPrefix("## ") { return .subheading(String(line.dropFirst(3))) }
                if line.hasPrefix("# ") { return .heading(String(line.dropFirst(2))) }
                for marker in ["- ", "• ", "* ", "– "] where line.hasPrefix(marker) {
                    return .bullet(String(line.dropFirst(marker.count)))
                }
                return .paragraph(line)
            }
    }
}

/// Text drawn with the fallback font (character not written yet).
struct FallbackText: Sendable {
    let text: String
    /// Left end of the baseline.
    let origin: CGPoint
    let fontSize: CGFloat
}

struct LaidOutPage: @unchecked Sendable {
    let number: Int
    /// All handwriting on the page as one filled path.
    let ink: CGPath
    let fallbacks: [FallbackText]
    var images: [PlacedImage] = []
}

/// A picture glued onto a page (slightly turned, like a real photo in an exercise book).
struct PlacedImage: @unchecked Sendable {
    let image: CGImage
    let rect: CGRect
    let rotation: CGFloat
}

/// Loads note pictures, downsized for drawing, and keeps them cached.
enum NoteImageLoader {
    private static let cache = NSCache<NSURL, CGImage>()

    static func image(at url: URL, maxPixels: Int = 1600) -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Lays text out on pages in the user's handwriting.
///
/// Variation is deterministic: each word's look depends on the note's seed,
/// the word itself and how often it already appeared. Editing one word
/// therefore leaves the look of all other words unchanged.
enum NoteLayout {
    static func layout(_ content: NoteContent, settings: PageSettings, font: HandwritingFont) -> [LaidOutPage] {
        let writer = PageWriter(settings: settings, font: font, seed: content.seed)
        writer.images = content.images

        if settings.showHeader && !content.header.isEmpty {
            writer.writeRightAligned(writer.normalize(content.header), scale: 0.8)
            writer.nextLine()
        }
        let title = writer.normalize(content.title).trimmingCharacters(in: .whitespaces)
        var previous: NoteBlock? = nil
        if !title.isEmpty {
            writer.writeParagraph(title, scale: 1.5, underline: true)
            writer.nextLine()
            previous = .blank
        }

        for block in NoteBlock.parse(writer.normalize(content.body)) {
            switch block {
            case .blank:
                writer.nextLine()
            case .heading(let text):
                if !writer.isAtPageTop && previous != .blank && previous != nil { writer.nextLine() }
                writer.writeParagraph(text, scale: 1.4, underline: true)
            case .subheading(let text):
                if !writer.isAtPageTop && previous != .blank && previous != nil { writer.nextLine() }
                writer.writeParagraph(text, scale: 1.15, underline: false)
            case .bullet(let text):
                writer.writeParagraph(text, scale: 1, underline: false, bullet: true)
            case .paragraph(let text):
                writer.writeParagraph(text, scale: 1, underline: false)
            case .image(let id):
                writer.placeImage(id)
            }
            previous = block
        }
        return writer.finish()
    }
}

/// Mutable state while laying out one note.
private final class PageWriter {
    let settings: PageSettings
    let font: HandwritingFont
    let seed: UInt64

    private var pages: [LaidOutPage] = []
    private var ink = CGMutablePath()
    private var fallbacks: [FallbackText] = []
    private var placedImages: [PlacedImage] = []
    var images: [UUID: NoteImageRef] = [:]
    private var line = 0
    private var occurrences: [String: Int] = [:]
    private var lineDrift: (amplitude: CGFloat, frequency: CGFloat, phase: CGFloat, slope: CGFloat, start: CGFloat)?

    private var x: CGFloat { settings.xHeight }
    private var leftEdge: CGFloat { settings.marginLeft }
    private var rightEdge: CGFloat { settings.pageSize.width - settings.marginRight }

    init(settings: PageSettings, font: HandwritingFont, seed: UInt64) {
        self.settings = settings
        self.font = font
        self.seed = seed
    }

    var isAtPageTop: Bool { line == 0 }

    /// Characters without a glyph are replaced by close equivalents first.
    func normalize(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\t", with: "    ")
        let replacements: [(String, String)] = [("…", "..."), ("·", "-"), ("•", "-"), ("—", "-"), ("–", "-"), ("‚", ","), ("‘", "'"), ("’", "'"), ("»", "\""), ("«", "\""), ("”", "“")]
        for (from, to) in replacements where !font.has(Character(from)) {
            result = result.replacingOccurrences(of: from, with: to)
        }
        if !font.has("ß") { result = result.replacingOccurrences(of: "ß", with: "ss") }
        return result
    }

    private func baseline(for line: Int) -> CGFloat {
        settings.marginTop + CGFloat(line + 1) * settings.lineSpacing
    }

    func nextLine() {
        line += 1
        lineDrift = nil
        if line >= settings.linesPerPage { newPage() }
    }

    private func newPage() {
        closePage()
        line = 0
        lineDrift = nil
    }

    private func closePage() {
        let number = pages.count + 1
        if settings.showPageNumbers {
            let text = "\(number)"
            let width = measure(text, scale: 0.8)
            let baselineY = settings.pageSize.height - settings.marginBottom / 2 + x * 0.4
            var rng = SeededRandom(seed: StableHash.combine(seed, 77, UInt64(number)))
            write(text, at: (settings.pageSize.width - width) / 2, baseline: baselineY, scale: 0.8, rng: &rng, drift: false)
        }
        pages.append(LaidOutPage(number: number, ink: ink.copy() ?? ink, fallbacks: fallbacks, images: placedImages))
        ink = CGMutablePath()
        fallbacks = []
        placedImages = []
    }

    /// Glues a picture onto the page, a few lines high, then continues below it.
    func placeImage(_ id: UUID) {
        guard let ref = images[id], let image = NoteImageLoader.image(at: ref.url) else { return }
        let spacing = settings.lineSpacing
        var height = CGFloat(max(3, ref.heightLines)) * spacing - spacing * 0.4
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        var width = height * aspect
        if width > settings.contentWidth * 0.95 {
            width = settings.contentWidth * 0.95
            height = width / aspect
        }
        let linesNeeded = Int((height / spacing).rounded(.up)) + 1
        if line + linesNeeded > settings.linesPerPage && line > 0 { newPage() }

        var rng = SeededRandom(seed: StableHash.combine(seed, 909, StableHash.of(id.uuidString)))
        let top = settings.marginTop + CGFloat(line) * spacing + spacing * 0.35
        let left = leftEdge + (settings.contentWidth - width) * (0.1 + 0.3 * rng.unit())
        placedImages.append(PlacedImage(image: image, rect: CGRect(x: left, y: top, width: width, height: height),
                                        rotation: 0.025 * rng.signed()))
        for _ in 0..<linesNeeded { nextLine() }
        if !ref.caption.isEmpty {
            writeParagraph(normalize(ref.caption), scale: 0.85, underline: false)
        }
    }

    func finish() -> [LaidOutPage] {
        if line > 0 || !ink.isEmpty || !fallbacks.isEmpty || !placedImages.isEmpty || pages.isEmpty {
            closePage()
        }
        return pages
    }

    // MARK: Writing

    func writeRightAligned(_ text: String, scale: CGFloat) {
        let width = measure(text, scale: scale)
        var rng = SeededRandom(seed: StableHash.combine(seed, 11, StableHash.of(text)))
        write(text, at: max(leftEdge, rightEdge - width), baseline: baseline(for: line), scale: scale, rng: &rng, drift: true)
    }

    /// Writes a paragraph with word wrap, then moves to the next line.
    func writeParagraph(_ text: String, scale: CGFloat, underline: Bool, bullet: Bool = false) {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else {
            nextLine()
            return
        }
        let indent: CGFloat = bullet ? x * 1.6 : 0
        let spaceWidth = font.wordSpacing * x * scale
        var lineStart = leftEdge + indent + jitterIndent()
        var cursor = lineStart
        var underlineStart = cursor

        if bullet {
            var rng = SeededRandom(seed: StableHash.combine(seed, 5, UInt64(line)))
            let marker = font.has("-") ? "-" : "•"
            write(marker, at: leftEdge + x * 0.2, baseline: baseline(for: line), scale: scale, rng: &rng, drift: true)
        }

        func finishLineUnderline() {
            if underline && cursor > underlineStart {
                drawUnderline(from: underlineStart, to: cursor - spaceWidth * 0.6, baseline: baseline(for: line), scale: scale)
            }
        }

        for word in words {
            var pieces = [word]
            let available = rightEdge - lineStart
            if measure(word, scale: scale) > available {
                pieces = split(word, maxWidth: available, scale: scale)
            }
            for piece in pieces {
                let width = measure(piece, scale: scale)
                if cursor + width > rightEdge && cursor > lineStart {
                    finishLineUnderline()
                    nextLine()
                    lineStart = leftEdge + indent + jitterIndent()
                    cursor = lineStart
                    underlineStart = cursor
                }
                let occurrence = occurrences[piece, default: 0]
                occurrences[piece] = occurrence + 1
                var rng = SeededRandom(seed: StableHash.combine(seed, StableHash.of(piece), UInt64(occurrence)))
                let advance = write(piece, at: cursor, baseline: baseline(for: line), scale: scale, rng: &rng, drift: true)
                cursor += advance + spaceWidth * (1 + 0.12 * font.variation * rng.signed())
            }
        }
        finishLineUnderline()
        nextLine()
    }

    private func jitterIndent() -> CGFloat {
        var rng = SeededRandom(seed: StableHash.combine(seed, 3, UInt64(pages.count), UInt64(line)))
        return x * 0.12 * font.variation * rng.unit()
    }

    /// Splits a word that is longer than a whole line.
    private func split(_ word: String, maxWidth: CGFloat, scale: CGFloat) -> [String] {
        var pieces: [String] = []
        var current = ""
        for character in word {
            let candidate = current + String(character)
            if !current.isEmpty && measure(candidate, scale: scale) > maxWidth {
                pieces.append(current)
                current = String(character)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// Width of a word without random variation.
    func measure(_ text: String, scale: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        for character in text {
            if character == " " {
                width += (font.wordSpacing - font.letterSpacing) * x * scale
                continue
            }
            if let variant = font.variants(for: character)?.first {
                width += (variant.advance + font.letterSpacing) * x * scale
            } else {
                let size = FallbackFont.size(forXHeight: x * scale)
                width += FallbackFont.width(of: String(character), size: size) + font.letterSpacing * x * scale
            }
        }
        return max(0, width - font.letterSpacing * x * scale)
    }

    /// Draws a word and returns its width.
    @discardableResult
    private func write(_ text: String, at start: CGFloat, baseline baselineY: CGFloat, scale: CGFloat,
                       rng: inout SeededRandom, drift: Bool) -> CGFloat {
        let variation = font.variation
        let shear = CGAffineTransform(a: 1, b: 0, c: -tan(font.slant), d: 1, tx: 0, ty: 0)
        var cursor = start
        var previous: (Character, Int)?
        var pendingFallback = ""
        var fallbackStart = cursor

        func flushFallback() {
            guard !pendingFallback.isEmpty else { return }
            let size = FallbackFont.size(forXHeight: x * scale)
            let y = baselineY + (drift ? self.drift(at: fallbackStart) : 0)
            fallbacks.append(FallbackText(text: pendingFallback, origin: CGPoint(x: fallbackStart, y: y), fontSize: size))
            pendingFallback = ""
        }

        for character in text {
            if character == " " {
                flushFallback()
                previous = nil
                cursor += (font.wordSpacing - font.letterSpacing) * x * scale
                continue
            }
            guard let options = font.variants(for: character), !options.isEmpty else {
                if pendingFallback.isEmpty { fallbackStart = cursor }
                pendingFallback.append(character)
                let size = FallbackFont.size(forXHeight: x * scale)
                cursor += FallbackFont.width(of: String(character), size: size) + font.letterSpacing * x * scale
                continue
            }
            flushFallback()

            var index = Int(rng.next() % UInt64(options.count))
            if let previous, previous.0 == character, previous.1 == index, options.count > 1 {
                index = (index + 1) % options.count
            }
            previous = (character, index)
            let variant = options[index]

            let size = x * scale * (1 + 0.035 * variation * rng.soft())
            let rotation = 0.028 * variation * rng.soft()
            let lift = x * scale * 0.035 * variation * rng.soft()
            let y = baselineY + lift + (drift ? self.drift(at: cursor) : 0)

            let transform = shear
                .concatenating(CGAffineTransform(scaleX: size, y: size))
                .concatenating(CGAffineTransform(rotationAngle: rotation))
                .concatenating(CGAffineTransform(translationX: cursor, y: y))
            ink.addPath(variant.outline, transform: transform)

            cursor += variant.advance * size + font.letterSpacing * x * scale * (1 + 0.25 * variation * rng.signed())
        }
        flushFallback()
        return max(0, cursor - start - font.letterSpacing * x * scale)
    }

    /// Slow up-and-down movement along a line, like writing without a ruler.
    private func drift(at position: CGFloat) -> CGFloat {
        if lineDrift == nil {
            var rng = SeededRandom(seed: StableHash.combine(seed, 101, UInt64(pages.count), UInt64(line)))
            let strength = font.variation
            lineDrift = (
                amplitude: x * 0.06 * strength * rng.unit(),
                frequency: 0.6 + rng.unit() * 0.8,
                phase: rng.unit() * 2 * .pi,
                slope: 0.006 * strength * rng.signed(),
                start: leftEdge
            )
        }
        guard let d = lineDrift else { return 0 }
        let t = (position - d.start) / max(settings.contentWidth, 1)
        return d.amplitude * sin(d.phase + t * 2 * .pi * d.frequency) + d.slope * (position - d.start)
    }

    private func drawUnderline(from start: CGFloat, to end: CGFloat, baseline baselineY: CGFloat, scale: CGFloat) {
        guard end > start else { return }
        var rng = SeededRandom(seed: StableHash.combine(seed, 404, UInt64(pages.count), UInt64(line)))
        let y = baselineY + x * 0.38 * scale
        let steps = 8
        var points: [CGPoint] = []
        var widths: [CGFloat] = []
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let px = start - x * 0.1 + (end - start + x * 0.2) * t
            points.append(CGPoint(x: px, y: y + drift(at: px) + x * 0.035 * font.variation * rng.soft() + t * x * 0.05 * rng.signed()))
            widths.append(x * font.penRatio * (0.9 + 0.15 * rng.unit()))
        }
        StrokeOutline.add(points: points, widths: widths, to: ink)
    }
}
