import PDFKit
import SwiftData
import XCTest
@testable import Margin

/// Synthetic "handwriting" for tests: simple shapes with known size.
private enum TestGlyphs {
    /// A box-like stroke from the baseline up to `top` (negative = above baseline).
    static func shape(width: Float = 0.6, top: Float = -1, bottom: Float = 0) -> [Stroke] {
        [[
            StrokePoint(x: 0, y: bottom, w: 1),
            StrokePoint(x: 0, y: top, w: 1),
            StrokePoint(x: width, y: top, w: 1),
            StrokePoint(x: width, y: bottom, w: 1),
        ]]
    }

    static func input(_ strokes: [Stroke], scale: Double = 1) -> GlyphInput {
        GlyphInput(uid: UUID(), strokes: strokes, scale: scale, baselineOffset: 0)
    }

    /// Every character of the charset with plausible proportions.
    static func fullSource() -> FontSource {
        var source = FontSource()
        for character in HandwritingCharset.all {
            let top: Float = HandwritingCharset.xHeightLetters.contains(character) ? -1 : -1.8
            let bottom: Float = "gjpqy".contains(character) ? 0.7 : 0
            source.glyphs[character] = [input(shape(top: top, bottom: bottom)), input(shape(width: 0.65, top: top, bottom: bottom))]
        }
        return source
    }
}

final class GlyphProcessingTests: XCTestCase {
    func testStrokeEncodingRoundTrip() {
        let strokes: [Stroke] = [
            [StrokePoint(x: 0, y: -1, w: 1.1), StrokePoint(x: 0.5, y: 0.25, w: 0.8)],
            [StrokePoint(x: 0.2, y: -1.4, w: 1)],
        ]
        XCTAssertEqual(GlyphStrokes.decode(GlyphStrokes.encode(strokes)), strokes)
        XCTAssertEqual(GlyphStrokes.decode(Data()), [])
        XCTAssertEqual(GlyphStrokes.decode(Data([1, 5])), [])
    }

    func testNormalizeUsesGuideLines() throws {
        let guide = CaptureGuide(size: CGSize(width: 300, height: 300))
        let raw = [[
            CapturedPoint(location: CGPoint(x: 50, y: guide.baseline), time: 0),
            CapturedPoint(location: CGPoint(x: 50, y: guide.xLine), time: 0.2),
            CapturedPoint(location: CGPoint(x: 50 + guide.xHeight, y: guide.xLine), time: 0.4),
        ]]
        let strokes = try XCTUnwrap(GlyphProcessing.normalize(raw, guide: guide))
        let points = strokes[0]
        XCTAssertEqual(points.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(points.first?.y ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(points[1].y, -1, accuracy: 0.001)
        XCTAssertEqual(points.last?.x ?? -1, 1, accuracy: 0.001)
        XCTAssertNil(GlyphProcessing.normalize([], guide: guide))
    }

    func testSimplifyDropsPointsOnAStraightLine() {
        let line = (0...20).map { StrokePoint(x: Float($0) / 20, y: 0, w: 1) }
        XCTAssertEqual(GlyphProcessing.simplify(line, tolerance: 0.01).count, 2)
    }

    func testFastStrokesAreThinner() {
        let slow = (0..<10).map { CapturedPoint(location: CGPoint(x: Double($0), y: 0), time: Double($0) * 0.05) }
        let fast = (0..<10).map { CapturedPoint(location: CGPoint(x: Double($0) * 40, y: 0), time: Double($0) * 0.005) }
        let slowWidth = GlyphProcessing.penWidths(for: slow)[5]
        let fastWidth = GlyphProcessing.penWidths(for: fast)[5]
        XCTAssertGreaterThan(slowWidth, fastWidth)
    }
}

final class HandwritingAnalysisTests: XCTestCase {
    func testScaleCorrectionWhenWritingSmallerThanGuide() {
        var glyphs: [String: [GlyphInput]] = [:]
        for letter in ["a", "c", "e", "m", "n", "o"] {
            glyphs[letter] = [TestGlyphs.input(TestGlyphs.shape(top: -0.8))]
        }
        let analysis = HandwritingAnalysis.analyze(glyphs)
        XCTAssertEqual(analysis.scaleCorrection, 1.25, accuracy: 0.01)
        XCTAssertEqual(analysis.baselineCorrection, 0, accuracy: 0.001)
        XCTAssertTrue(analysis.outliers.isEmpty)
        XCTAssertEqual(analysis.captured, 6)
    }

    func testOutlierIsDetected() {
        var glyphs: [String: [GlyphInput]] = [:]
        for letter in ["a", "c", "e", "m", "n"] {
            glyphs[letter] = [TestGlyphs.input(TestGlyphs.shape(top: -1))]
        }
        glyphs["o"] = [TestGlyphs.input(TestGlyphs.shape(top: -1.6))]
        let outliers = HandwritingAnalysis.analyze(glyphs).outliers
        XCTAssertEqual(outliers.map(\.character), ["o"])
        XCTAssertEqual(outliers.first?.suggestedScale ?? 0, 1 / 1.6, accuracy: 0.01)
    }

    func testLetterSpacingFromSampleWord() throws {
        // Two letters of width 0.6 written 0.3 apart → total width 1.5.
        var glyphs: [String: [GlyphInput]] = [:]
        glyphs["a"] = [TestGlyphs.input(TestGlyphs.shape(width: 0.6))]
        glyphs["n"] = [TestGlyphs.input(TestGlyphs.shape(width: 0.6))]
        let word: [Stroke] = TestGlyphs.shape(width: 0.6) + [TestGlyphs.shape(width: 0.6)[0].map {
            StrokePoint(x: $0.x + 0.9, y: $0.y, w: $0.w)
        }]
        let gap = try XCTUnwrap(HandwritingAnalysis.letterSpacing(word: "an", written: word, glyphs: glyphs))
        XCTAssertEqual(gap, 0.3, accuracy: 0.01)
        XCTAssertNil(HandwritingAnalysis.letterSpacing(word: "ab", written: word, glyphs: glyphs))
    }
}

final class HandwritingLayoutTests: XCTestCase {
    func testMissingUmlautIsBuiltFromBaseLetter() {
        var source = FontSource()
        source.glyphs["a"] = [TestGlyphs.input(TestGlyphs.shape())]
        let font = HandwritingFont(source: source, penRatio: 0.15)
        XCTAssertTrue(font.has("ä"))
        XCTAssertFalse(font.has("ö"))
        let dotted = font.variants(for: "ä")?.first?.outline.boundingBoxOfPath
        let plain = font.variants(for: "a")?.first?.outline.boundingBoxOfPath
        XCTAssertLessThan(dotted?.minY ?? 0, (plain?.minY ?? 0) - 0.2)
    }

    func testParsesMarkup() {
        let blocks = NoteBlock.parse("# Titel\n## Unter\n- Punkt\n\nText")
        XCTAssertEqual(blocks, [.heading("Titel"), .subheading("Unter"), .bullet("Punkt"), .blank, .paragraph("Text")])
    }

    func testLayoutIsDeterministic() {
        let font = HandwritingFont(source: TestGlyphs.fullSource(), penRatio: 0.15)
        let content = NoteContent(title: "Funktionen", header: "Mathe · 02.11.2026", body: "Eine Funktion ordnet jedem x genau ein y zu.", seed: 7)
        let a = NoteLayout.layout(content, settings: PageSettings(), font: font)
        let b = NoteLayout.layout(content, settings: PageSettings(), font: font)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].ink.boundingBoxOfPath, b[0].ink.boundingBoxOfPath)
        XCTAssertTrue(a[0].fallbacks.isEmpty)

        var reseeded = content
        reseeded.seed = 8
        let c = NoteLayout.layout(reseeded, settings: PageSettings(), font: font)
        XCTAssertNotEqual(a[0].ink.boundingBoxOfPath, c[0].ink.boundingBoxOfPath)
    }

    func testLongTextFlowsOntoMorePagesAndStaysInsideMargins() {
        let font = HandwritingFont(source: TestGlyphs.fullSource(), penRatio: 0.15)
        let paragraph = String(repeating: "Lernen macht Spass und ist wichtig. ", count: 40)
        let body = Array(repeating: paragraph, count: 4).joined(separator: "\n")
        let settings = PageSettings()
        let pages = NoteLayout.layout(NoteContent(title: "", header: "", body: body, seed: 1), settings: settings, font: font)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.number), Array(1...pages.count))
        for page in pages {
            let box = page.ink.boundingBoxOfPath
            XCTAssertGreaterThan(box.minX, settings.marginLeft - settings.xHeight)
            XCTAssertLessThan(box.maxX, settings.pageSize.width - settings.marginRight + settings.xHeight * 1.5)
        }
    }

    func testWithoutHandwritingEverythingUsesFallbackFont() {
        let font = HandwritingFont(source: .empty, penRatio: 0.15)
        var settings = PageSettings()
        settings.showPageNumbers = false
        let pages = NoteLayout.layout(NoteContent(title: "", header: "", body: "Hallo Welt", seed: 1), settings: settings, font: font)
        XCTAssertEqual(pages.count, 1)
        XCTAssertTrue(pages[0].ink.isEmpty)
        XCTAssertEqual(pages[0].fallbacks.map(\.text).joined(), "HalloWelt")
    }

    func testPDFHasOneA4PagePerPage() throws {
        let font = HandwritingFont(source: TestGlyphs.fullSource(), penRatio: 0.15)
        let settings = PageSettings()
        let body = String(repeating: "Notiz ", count: 900)
        let pages = NoteLayout.layout(NoteContent(title: "Test", header: "", body: body, seed: 3), settings: settings, font: font)
        let data = PageRenderer.pdf(pages: pages, settings: settings, title: "Test")
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, pages.count)
        let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 595.28, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 841.89, accuracy: 0.5)
    }
}

@MainActor
final class HandwritingPersistenceTests: XCTestCase {
    override func setUp() async throws {
        ReminderService.isEnabled = false
    }

    func testPhaseOneDatabaseMigratesToPhaseTwo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        do {
            let v1 = Schema(versionedSchema: MarginSchemaV1.self)
            let container = try ModelContainer(for: v1, configurations: ModelConfiguration(schema: v1, url: url))
            let context = ModelContext(container)
            context.insert(SchoolSubject(name: "Biologie", colorKey: "green"))
            try context.save()
        }

        let container = try Persistence.makeContainer(configuration: ModelConfiguration(schema: Persistence.schema, url: url))
        let context = ModelContext(container)
        let subjects = try context.fetch(FetchDescriptor<SchoolSubject>())
        XCTAssertEqual(subjects.map(\.name), ["Biologie"])

        context.insert(NoteDocument(title: "Zellen"))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NoteDocument>()), 1)
    }

    func testBackupIncludesHandwritingAndNotes() throws {
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext

        let profile = HandwritingProfile(name: "Meine Handschrift")
        profile.letterSpacing = 0.21
        context.insert(profile)
        let glyph = GlyphSample(character: "a", strokeData: GlyphStrokes.encode(TestGlyphs.shape()))
        glyph.scale = 1.1
        context.insert(glyph)
        glyph.profile = profile
        let note = NoteDocument(title: "Zellen")
        note.body = "# Zellen\n- Zellkern"
        note.profileUID = profile.uid
        note.paper = .squared
        context.insert(note)
        try context.save()

        let data = try BackupService.export(context: context, settings: nil)
        try BackupService.restore(BackupService.decode(data), context: context, settings: nil)

        let restoredProfile = try XCTUnwrap(context.fetch(FetchDescriptor<HandwritingProfile>()).first)
        XCTAssertEqual(restoredProfile.letterSpacing, 0.21)
        XCTAssertEqual(restoredProfile.glyphs?.count, 1)
        XCTAssertEqual(restoredProfile.glyphs?.first?.scale, 1.1)
        XCTAssertEqual(GlyphStrokes.decode(restoredProfile.glyphs?.first?.strokeData ?? Data()), TestGlyphs.shape())

        let restoredNote = try XCTUnwrap(context.fetch(FetchDescriptor<NoteDocument>()).first)
        XCTAssertEqual(restoredNote.body, "# Zellen\n- Zellkern")
        XCTAssertEqual(restoredNote.paper, .squared)
        XCTAssertEqual(restoredNote.profileUID, restoredProfile.uid)
    }

    func testVersionOneBackupStillLoads() throws {
        let json = """
        {"format":"margin-backup","version":1,"exportedAt":"2026-11-02T10:00:00Z","appVersion":"0.2.0",
         "subjects":[],"topics":[],"lessons":[],"tasks":[],"subtasks":[],"exams":[],"events":[],"attachments":[],"holidays":[]}
        """
        let file = try BackupService.decode(Data(json.utf8))
        XCTAssertNil(file.notes)
    }
}
