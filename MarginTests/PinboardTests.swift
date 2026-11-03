import SwiftData
import XCTest
@testable import Margin

final class PinLinkTests: XCTestCase {
    func testRecognisesYouTubeLinks() {
        XCTAssertEqual(PinLinks.youTubeID(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=20")!), "dQw4w9WgXcQ")
        XCTAssertEqual(PinLinks.youTubeID(URL(string: "https://youtu.be/dQw4w9WgXcQ")!), "dQw4w9WgXcQ")
        XCTAssertEqual(PinLinks.youTubeID(URL(string: "https://youtube.com/shorts/abc123")!), "abc123")
        XCTAssertNil(PinLinks.youTubeID(URL(string: "https://de.wikipedia.org/wiki/Mitose")!))
        XCTAssertTrue(PinLinks.isVideoHost(URL(string: "https://vimeo.com/123")!))
    }

    func testReadsHTMLTitle() {
        XCTAssertEqual(PinLinks.htmlTitle("<html><head><TITLE lang=de> Mitose &amp; Meiose </TITLE></head>"), "Mitose & Meiose")
        XCTAssertNil(PinLinks.htmlTitle("<html><body>kein Titel</body></html>"))
    }
}

@MainActor
final class PinboardToolTests: XCTestCase {
    func testTutorCanPinVideosAndStickyNotes() throws {
        ReminderService.isEnabled = false
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        let subject = SchoolSubject(name: "Biologie", colorKey: "green")
        context.insert(subject)
        try context.save()

        _ = MarginTools.call("pin_to_board", input: ["subject": "Biologie", "url": "https://youtu.be/abc", "title": "Mitose erklärt"], context: context)
        _ = MarginTools.call("pin_to_board", input: ["subject": "Biologie", "text": "Prophase, Metaphase, Anaphase, Telophase"], context: context)
        let pins = try context.fetch(FetchDescriptor<PinItem>(sortBy: [SortDescriptor(\.sortIndex)]))
        XCTAssertEqual(pins.map(\.kind), [.video, .sticky])
        XCTAssertEqual(pins.map(\.sortIndex), [0, 1])
        XCTAssertTrue(pins.allSatisfy { $0.subjectUID == subject.uid })
    }
}
