import SwiftData
import XCTest
@testable import Margin

final class NoteBlockTests: XCTestCase {
    func testParsesNotionStyleBlocks() {
        let blocks = NoteBlock.parse("- [ ] offen\n- [x] fertig\n> Merke dir das\n---\n| A | B |\n|---|---|\n| 1 | 2 |\nSiehe [[Zellen]]")
        XCTAssertEqual(blocks, [
            .checkbox("offen", checked: false), .checkbox("fertig", checked: true), .callout("Merke dir das"),
            .divider, .tableRow(["A", "B"]), .tableRow([]), .tableRow(["1", "2"]), .paragraph("Siehe Zellen"),
        ])
    }

    func testLinksAreFoundButImagesAreNot() {
        let image = NoteBlock.imageLine(UUID())
        let text = "Vgl. [[Zellen]] und [[ Mitose ]], nochmal [[zellen]]\n\(image)"
        XCTAssertEqual(NoteBlock.links(in: text), ["Zellen", "Mitose"])
        XCTAssertEqual(NoteBlock.parse(image).count, 1)
        if case .image = NoteBlock.parse(image)[0] {} else { XCTFail("image line must stay an image") }
    }

    func testStripKeepsCheckboxText() {
        XCTAssertEqual(LineStyle.strip("- [ ] Vokabeln"), "Vokabeln")
        XCTAssertEqual(LineStyle.strip("> Merke"), "Merke")
        XCTAssertEqual(LineStyle.strip("- Punkt"), "Punkt")
    }

    func testTablesChecklistsAndDividersAreDrawnInInk() {
        let font = HandwritingFont(source: TestGlyphs.fullSource(), penRatio: 0.15)
        // Without the page number, which would stretch the ink to the bottom of the page.
        var settings = PageSettings()
        settings.showPageNumbers = false
        let plain = NoteLayout.layout(NoteContent(title: "", header: "", body: "Text", seed: 3), settings: settings, font: font)
        let body = "Text\n- [x] erledigt\n> Merke\n---\n| Zeit | Wert |\n|---|---|\n| 1 | 2 |"
        let rich = NoteLayout.layout(NoteContent(title: "", header: "", body: body, seed: 3), settings: settings, font: font)
        XCTAssertEqual(rich.count, 1)
        XCTAssertGreaterThan(rich[0].ink.boundingBoxOfPath.height, plain[0].ink.boundingBoxOfPath.height * 3)
        XCTAssertLessThanOrEqual(rich[0].ink.boundingBoxOfPath.maxX, settings.pageSize.width - settings.marginRight + 8)
    }

    func testEveryTemplateRenders() {
        let font = HandwritingFont(source: TestGlyphs.fullSource(), penRatio: 0.15)
        for template in NoteTemplate.allCases {
            let pages = NoteLayout.layout(NoteContent(title: template.title, header: "", body: template.body, seed: 1),
                                          settings: PageSettings(), font: font)
            XCTAssertFalse(pages.isEmpty, template.title)
        }
    }
}

@MainActor
final class NotePagesTests: XCTestCase {
    func testSubpagesBacklinksAndDeleting() throws {
        ReminderService.isEnabled = false
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        let parent = NoteDocument(title: "Biologie")
        parent.body = "Themen: [[Zellen]]"
        context.insert(parent)
        let child = NotePages.addSubpage(to: parent, title: "Zellen", context: context)
        let grandchild = NotePages.addSubpage(to: child, title: "Mitose", context: context)

        var notes = try context.fetch(FetchDescriptor<NoteDocument>())
        var metas = try context.fetch(FetchDescriptor<NoteMeta>())
        XCTAssertEqual(NotePages.children(of: parent, notes: notes, metas: metas).map(\.title), ["Zellen"])
        XCTAssertEqual(NotePages.parent(of: grandchild, notes: notes, metas: metas)?.title, "Zellen")
        XCTAssertEqual(NotePages.linked(from: parent, notes: notes).map(\.title), ["Zellen"])
        XCTAssertEqual(NotePages.backlinks(to: child, notes: notes).map(\.title), ["Biologie"])

        NotePages.delete(child, context: context)
        notes = try context.fetch(FetchDescriptor<NoteDocument>())
        metas = try context.fetch(FetchDescriptor<NoteMeta>())
        XCTAssertEqual(NotePages.parent(of: grandchild, notes: notes, metas: metas)?.title, "Biologie", "subpages move up")
        XCTAssertEqual(NotePages.missingLinks(in: parent, notes: notes), ["Zellen"])
    }
}

final class HomeworkParserTests: XCTestCase {
    private var calendar: Calendar { .school }
    /// Wednesday, 4 November 2026.
    private var wednesday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))! }

    private func day(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }

    func testReadsTitleSubjectAndWeekday() {
        let text = "Hausaufgaben\nMathe: S. 34 Nr. 5a und 6\nbis Freitag"
        let suggestion = HomeworkParser.suggest(from: text, subjects: ["Deutsch", "Mathematik"], today: wednesday)
        XCTAssertEqual(suggestion.title, "Mathe: S. 34 Nr. 5a und 6")
        XCTAssertEqual(suggestion.subjectName, "Mathematik")
        XCTAssertEqual(day(suggestion.dueDate), DateComponents(year: 2026, month: 11, day: 6))
    }

    func testDueDates() {
        XCTAssertEqual(day(HomeworkParser.dueDate(in: "bis zum 12.11.", today: wednesday, calendar: calendar)),
                       DateComponents(year: 2026, month: 11, day: 12))
        XCTAssertEqual(day(HomeworkParser.dueDate(in: "Abgabe 3.1.", today: wednesday, calendar: calendar)),
                       DateComponents(year: 2027, month: 1, day: 3), "a past day without a year means next year")
        XCTAssertEqual(day(HomeworkParser.dueDate(in: "bis morgen lesen", today: wednesday, calendar: calendar)),
                       DateComponents(year: 2026, month: 11, day: 5))
        XCTAssertEqual(day(HomeworkParser.dueDate(in: "für übermorgen", today: wednesday, calendar: calendar)),
                       DateComponents(year: 2026, month: 11, day: 6))
        XCTAssertEqual(day(HomeworkParser.dueDate(in: "bis nächsten Mittwoch", today: wednesday, calendar: calendar)),
                       DateComponents(year: 2026, month: 11, day: 11), "the same weekday means next week")
        XCTAssertNil(HomeworkParser.dueDate(in: "Arbeitsblatt bearbeiten", today: wednesday, calendar: calendar))
    }

    func testLongTitlesAreShortened() {
        let title = HomeworkParser.cleanTitle("HA: " + String(repeating: "Lies den Text ", count: 10))
        XCTAssertTrue(title.hasPrefix("Lies"))
        XCTAssertLessThanOrEqual(title.count, 72)
    }
}
