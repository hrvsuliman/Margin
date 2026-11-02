import SwiftData
import UIKit
import XCTest
@testable import Margin

final class GradeMathTests: XCTestCase {
    private func entry(_ value: Double, written: Bool = true, weight: Double = 1) -> GradeEntry {
        GradeEntry(value: value, weight: weight, isWritten: written)
    }

    func testWrittenAndOralAreWeighted() throws {
        let entries = [entry(2), entry(3), entry(1, written: false)]
        let average = try XCTUnwrap(GradeMath.average(entries, writtenShare: 0.5))
        XCTAssertEqual(average, 1.75, accuracy: 0.0001)
        XCTAssertEqual(GradeMath.average([entry(2), entry(4)], writtenShare: 0.5) ?? 0, 3, accuracy: 0.0001)
        XCTAssertNil(GradeMath.average([], writtenShare: 0.5))
    }

    func testWeightsCount() {
        XCTAssertEqual(GradeMath.weightedAverage([entry(1, weight: 2), entry(4)]) ?? 0, 2, accuracy: 0.0001)
    }

    func testNeededNextGrade() {
        // Written 3 and 3, oral 2: 0.5 · (6 + x) / 3 + 0.5 · 2 ≤ 2.5 → x ≤ 3, so a 3 is enough.
        let entries = [entry(3), entry(3), entry(2, written: false)]
        XCTAssertEqual(GradeMath.neededNext(entries, writtenShare: 0.5, target: 2.5, scale: .grades), 3.0)
        XCTAssertEqual(GradeMath.neededNext(entries, writtenShare: 0.5, target: 2.4, scale: .grades), 2.3)
        // A 1.0 average is out of reach.
        XCTAssertNil(GradeMath.neededNext(entries, writtenShare: 0.5, target: 1.0, scale: .grades))
    }

    func testPointsScale() {
        let entries = [entry(8), entry(10)]
        XCTAssertEqual(GradeMath.neededNext(entries, writtenShare: 0.5, target: 10, scale: .points), 12)
        XCTAssertEqual(GradeScale.points.label(11), "11 P.")
        XCTAssertEqual(GradeScale.grades.label(2.3), "2-")
        XCTAssertEqual(GradeScale.grades.label(1.7), "2+")
        XCTAssertEqual(GradeScale.grades.average(2.346), "2,35")
    }
}

final class NoteImageLayoutTests: XCTestCase {
    func testImageLinesAreParsed() {
        let id = UUID()
        XCTAssertEqual(NoteBlock.parse(NoteBlock.imageLine(id)), [.image(id)])
        XCTAssertEqual(NoteBlock.parse("[[Bild:kaputt]]"), [.paragraph("[[Bild:kaputt]]")])
    }

    func testPictureIsGluedOntoThePageAndTextFlowsBelow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let id = UUID()
        var source = FontSource()
        for character in HandwritingCharset.all {
            source.glyphs[character] = [GlyphInput(uid: UUID(), strokes: [[
                StrokePoint(x: 0, y: 0, w: 1), StrokePoint(x: 0, y: -1, w: 1), StrokePoint(x: 0.5, y: -1, w: 1),
            ]], scale: 1, baselineOffset: 0)]
        }
        let font = HandwritingFont(source: source, penRatio: 0.15)
        var content = NoteContent(title: "", header: "", body: "Oben\n\(NoteBlock.imageLine(id))\nUnten", seed: 1)
        content.images[id] = NoteImageRef(url: url, heightLines: 6, caption: "Zelle")
        var settings = PageSettings()
        settings.showPageNumbers = false
        let pages = NoteLayout.layout(content, settings: settings, font: font)

        XCTAssertEqual(pages.count, 1)
        let placed = try XCTUnwrap(pages[0].images.first)
        XCTAssertEqual(placed.rect.height, 6 * settings.lineSpacing - settings.lineSpacing * 0.4, accuracy: 0.5)
        XCTAssertEqual(placed.rect.width / placed.rect.height, 4.0 / 3.0, accuracy: 0.02)
        // The text after the picture starts below it.
        XCTAssertGreaterThan(pages[0].ink.boundingBoxOfPath.maxY, placed.rect.maxY)
    }
}

@MainActor
final class StudySheetTests: XCTestCase {
    func testSheetCollectsTopicNotesSubtopicsAndCards() throws {
        ReminderService.isEnabled = false
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        let topic = Topic(title: "Zellen", subject: nil)
        topic.details = "Kleinste Einheit des Lebens"
        context.insert(topic)
        let child = Topic(title: "Mitose", subject: nil)
        context.insert(child)
        child.parent = topic
        let card = Flashcard(front: "ATP", back: "Energieträger")
        card.topicUID = topic.uid
        context.insert(card)
        try context.save()

        let body = StudySheet.body(for: [topic], cards: [card], heading: nil)
        XCTAssertEqual(body, "## Zellen\nKleinste Einheit des Lebens\n- ATP: Energieträger\n\n- Mitose")
        XCTAssertTrue(NoteFlashcards.extract(from: body).isEmpty, "a study sheet must not create duplicate cards")
    }
}
