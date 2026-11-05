import SwiftData
import XCTest
@testable import Margin

final class AppRouteTests: XCTestCase {
    func testRoutesFromSearchAndLinks() {
        let id = UUID()
        XCTAssertEqual(AppRoute(identifier: "note:\(id)"), .note(id))
        XCTAssertEqual(AppRoute(identifier: "today"), .today)
        XCTAssertNil(AppRoute(identifier: "note:kaputt"))
        XCTAssertEqual(AppRoute(url: URL(string: "margin://task/\(id)")!), .task(id))
        XCTAssertEqual(AppRoute(url: URL(string: "margin://today")!), .today)
        XCTAssertNil(AppRoute(url: URL(string: "https://example.com/task/\(id)")!))
    }
}

final class SummaryParsingTests: XCTestCase {
    func testOnlyTodosOfTheTaskSectionAreTaken() {
        let summary = """
        ## Zusammenfassung
        Es ging um Zellen.
        ## Wichtig
        - [ ] das ist keine Aufgabe
        ## Aufgaben
        - [ ] S. 34 Nr. 5 bis Freitag
        - [x] schon erledigt
        - [ ] Vokabeln lernen
        ## Karteikarten
        Mitose :: Zellteilung
        """
        XCTAssertEqual(NoteSummarizer.todos(in: summary), ["S. 34 Nr. 5 bis Freitag", "Vokabeln lernen"])
    }
}

@MainActor
final class CalendarPlanTests: XCTestCase {
    func testPlansExamsTasksAndSessions() throws {
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        let math = SchoolSubject(name: "Mathematik", colorKey: "blue")
        context.insert(math)
        let day = Calendar.school.addingDays(3, to: Calendar.school.startOfDay(for: .now))
        let exam = Exam(title: "Klassenarbeit", kind: .classTest, date: day, subject: math)
        context.insert(exam)
        let open = SchoolTask(title: "S. 34", subject: math, dueDate: day)
        let done = SchoolTask(title: "Fertig", subject: math, dueDate: day)
        context.insert(open)
        context.insert(done)
        done.status = .done
        let session = StudySession(date: day.addingTimeInterval(15 * 3600), minutes: 30, kind: .free)
        session.subjectUID = math.uid
        context.insert(session)
        try context.save()

        let all = CalendarSync.planned(exams: [exam], tasks: [open, done], sessions: [session], subjects: [math],
                                       includeTasks: true, includeSessions: true)
        XCTAssertEqual(all.map(\.key).sorted(), ["exam-\(exam.uid)", "session-\(session.uid)", "task-\(open.uid)"].sorted())
        XCTAssertEqual(all.first { $0.key.hasPrefix("exam") }?.title, "Mathematik: Klassenarbeit")
        XCTAssertTrue(all.first { $0.key.hasPrefix("exam") }?.allDay ?? false)
        XCTAssertEqual(all.first { $0.key.hasPrefix("session") }?.title, "Lernen: Mathematik")

        let examsOnly = CalendarSync.planned(exams: [exam], tasks: [open], sessions: [session], subjects: [math],
                                             includeTasks: false, includeSessions: false)
        XCTAssertEqual(examsOnly.count, 1)
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testCurrentNextAndRefreshTimes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = WidgetSnapshot(generatedAt: now)
        snapshot.lessons = [
            .init(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(2100), subject: "Mathe", room: "1",
                  colorKey: "blue", cancelled: false, changed: false, subjectID: nil),
            .init(start: now.addingTimeInterval(2400), end: now.addingTimeInterval(5100), subject: "Bio", room: "2",
                  colorKey: "green", cancelled: true, changed: true, subjectID: nil),
            .init(start: now.addingTimeInterval(5400), end: now.addingTimeInterval(8100), subject: "Deutsch", room: "3",
                  colorKey: "red", cancelled: false, changed: false, subjectID: nil),
        ]
        XCTAssertEqual(snapshot.currentOrNextLesson(at: now)?.subject, "Mathe")
        XCTAssertEqual(snapshot.currentOrNextLesson(at: now.addingTimeInterval(2200))?.subject, "Deutsch", "cancelled lessons are skipped")
        XCTAssertNil(snapshot.currentOrNextLesson(at: now.addingTimeInterval(9000)))
        XCTAssertEqual(snapshot.refreshDates(after: now).first, now.addingTimeInterval(2100))
    }
}
