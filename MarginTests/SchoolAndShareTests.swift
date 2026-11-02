import SwiftData
import XCTest
@testable import Margin

final class SchoolImportTests: XCTestCase {
    func testUntisPeriodBecomesLesson() throws {
        let period: [String: Any] = [
            "id": 4711, "date": 20261104, "startTime": 755, "endTime": 840, "code": "cancelled",
            "su": [["id": 1, "name": "M", "longname": "Mathematik"]], "ro": [["name": "204"]],
            "te": [["name": "SCH"]], "substText": "Selbststudium",
        ]
        let lesson = try XCTUnwrap(UntisClient.lesson(period))
        XCTAssertEqual(lesson.id, "4711")
        XCTAssertEqual(lesson.subject, "Mathematik")
        XCTAssertEqual(lesson.room, "204")
        XCTAssertEqual(lesson.status, .cancelled)
        XCTAssertEqual(lesson.info, "Selbststudium")
        let calendar = Calendar.school
        XCTAssertEqual(calendar.minuteOfDay(lesson.start), 7 * 60 + 55)
        XCTAssertEqual(calendar.component(.day, from: lesson.start), 4)
        XCTAssertEqual(UntisClient.untisDate(lesson.start), 20261104)
    }

    func testICalFeedIsParsed() {
        let ics = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        UID:abc-1\r
        DTSTART;TZID=Europe/Berlin:20261104T080000\r
        DTEND;TZID=Europe/Berlin:20261104T084500\r
        SUMMARY:Deutsch\r
        LOCATION:R 12\r
        DESCRIPTION:Gedichtanalyse\\, Teil 2\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:abc-2\r
        DTSTART:20261104T100000Z\r
        DTEND:20261104T104500Z\r
        SUMMARY:Englisch\r
        STATUS:CANCELLED\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let lessons = ICalFeed.parse(ics)
        XCTAssertEqual(lessons.map(\.subject), ["Deutsch", "Englisch"])
        XCTAssertEqual(lessons[0].room, "R 12")
        XCTAssertEqual(lessons[0].info, "Gedichtanalyse, Teil 2")
        XCTAssertEqual(lessons[1].status, .cancelled)
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(berlin.component(.hour, from: lessons[0].start), 8)
        XCTAssertEqual(berlin.component(.hour, from: lessons[1].start), 11, "10:00 UTC is 11:00 in Berlin in November")
    }

    @MainActor
    func testApplyMatchesSubjectsAndReportsNewChanges() throws {
        ReminderService.isEnabled = false
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        context.insert(SchoolSubject(name: "Mathematik", colorKey: "blue"))
        try context.save()
        let start = Date.now.addingTimeInterval(3600)
        var lesson = ImportedLesson(id: "1", start: start, end: start.addingTimeInterval(2700), subject: "Mathematik",
                                    room: "204", teacher: "", status: .normal, info: "")
        let sync = SchoolSync.shared
        XCTAssertTrue(sync.apply([lesson], source: "untis", context: context).isEmpty)
        lesson.status = .cancelled
        XCTAssertEqual(sync.apply([lesson], source: "untis", context: context).map(\.id), ["1"], "a new cancellation is reported")
        XCTAssertTrue(sync.apply([lesson], source: "untis", context: context).isEmpty, "…but only once")

        let entries = try context.fetch(FetchDescriptor<TimetableEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries[0].subjectUID)

        let agenda = Agenda(lessons: [], exams: [], tasks: [], events: [], holidays: [], entries: entries,
                            subjects: try context.fetch(FetchDescriptor<SchoolSubject>()))
        let items = agenda.items(on: start)
        XCTAssertEqual(items.first?.title, "Mathematik")
        XCTAssertTrue(items.first?.isChange ?? false)
    }
}

@MainActor
final class ShareTests: XCTestCase {
    func testDeckRoundTrip() throws {
        ReminderService.isEnabled = false
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        context.insert(SchoolSubject(name: "Biologie", colorKey: "green"))
        try context.save()

        let url = try ShareService.deck(title: "Zellen", subject: "Biologie",
                                        cards: [Flashcard(front: "Mitose", back: "Zellteilung")])
        XCTAssertEqual(url.pathExtension, "margin")
        let file = try XCTUnwrap(ShareService.read(Data(contentsOf: url)))
        XCTAssertEqual(file.cards?.first?.front, "Mitose")
        XCTAssertEqual(ShareService.importFile(file, context: context), "1 Karteikarten importiert")
        let card = try XCTUnwrap(context.fetch(FetchDescriptor<Flashcard>()).first)
        XCTAssertNotNil(card.subjectUID, "the subject is matched by name")
        XCTAssertNil(ShareService.read(Data("{}".utf8)))
    }

    func testTranscriptBecomesParagraphs() {
        let text = "Eins. Zwei. Drei. Vier. Fünf."
        XCTAssertEqual(Transcriber.paragraphs(text), "Eins. Zwei. Drei. Vier.\n\nFünf.")
    }
}
