import SwiftData
import XCTest
@testable import Margin

@MainActor
final class PersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let calendar = Calendar.school

    override func setUp() async throws {
        ReminderService.isEnabled = false
        container = try Persistence.inMemoryContainer()
    }

    override func tearDown() async throws {
        container = nil
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    func testTaskOverdueRules() {
        let task = SchoolTask(title: "Vokabeln", dueDate: date(2026, 11, 2))
        context.insert(task)
        // Due "on Monday" without a time: overdue only from Tuesday.
        XCTAssertFalse(task.isOverdue(now: date(2026, 11, 2, 23)))
        XCTAssertTrue(task.isOverdue(now: date(2026, 11, 3, 0)))
        task.status = .done
        XCTAssertFalse(task.isOverdue(now: date(2026, 11, 5)))
        XCTAssertNotNil(task.completedAt)
        task.status = .open
        XCTAssertNil(task.completedAt)
    }

    func testAgendaHidesLessonsOnHolidays() throws {
        let math = SchoolSubject(name: "Mathematik", colorKey: "blue")
        context.insert(math)
        let lesson = Lesson(subject: nil, weekday: 1, startMinute: 480, endMinute: 570)
        context.insert(lesson)
        lesson.subject = math
        let holiday = Holiday(name: "Herbstferien", start: date(2026, 11, 2), end: date(2026, 11, 6))
        context.insert(holiday)
        try context.save()

        let agenda = Agenda(lessons: [lesson], exams: [], tasks: [], events: [], holidays: [holiday])
        let duringHoliday = agenda.items(on: date(2026, 11, 2))
        XCTAssertEqual(duringHoliday.count, 1)
        XCTAssertTrue(duringHoliday[0].isHoliday)

        let afterHoliday = agenda.items(on: date(2026, 11, 9))
        XCTAssertEqual(afterHoliday.map(\.title), ["Mathematik"])
        XCTAssertEqual(afterHoliday.first?.start, date(2026, 11, 9, 8))
    }

    func testBackupRoundTripKeepsDataAndRelationships() throws {
        let math = SchoolSubject(name: "Mathematik", colorKey: "blue")
        math.teacher = "Frau Schmidt"
        context.insert(math)

        let lesson = Lesson(subject: nil, weekday: 2, startMinute: 590, endMinute: 680, room: "204")
        context.insert(lesson)
        lesson.subject = math

        let analysis = Topic(title: "Analysis", subject: nil)
        context.insert(analysis)
        analysis.subject = math
        let derivatives = Topic(title: "Ableitungen", subject: nil)
        context.insert(derivatives)
        derivatives.subject = math
        derivatives.parent = analysis

        let exam = Exam(title: "", kind: .classTest, date: date(2026, 11, 18, 8), subject: nil)
        context.insert(exam)
        exam.subject = math

        let task = SchoolTask(title: "S. 42 Nr. 3", kind: .homework, dueDate: date(2026, 11, 4))
        context.insert(task)
        task.subject = math
        task.topic = derivatives
        task.exam = exam
        let step = Subtask(title: "a)", sortIndex: 0, isDone: true)
        context.insert(step)
        step.task = task

        let event = CalendarEvent(title: "Theater-AG", start: date(2026, 11, 5, 15), end: date(2026, 11, 5, 17), category: .school)
        event.recurrence = .weekly
        context.insert(event)
        context.insert(Holiday(name: "Weihnachtsferien", start: date(2026, 12, 23), end: date(2027, 1, 6)))
        try context.save()

        let data = try BackupService.export(context: context, settings: nil)
        BackupService.deleteEverything(context: context)
        XCTAssertEqual(try count(SchoolSubject.self), 0)
        XCTAssertEqual(try count(SchoolTask.self), 0)

        try BackupService.restore(BackupService.decode(data), context: context, settings: nil)

        XCTAssertEqual(try count(SchoolSubject.self), 1)
        XCTAssertEqual(try count(Lesson.self), 1)
        XCTAssertEqual(try count(Topic.self), 2)
        XCTAssertEqual(try count(Exam.self), 1)
        XCTAssertEqual(try count(SchoolTask.self), 1)
        XCTAssertEqual(try count(Subtask.self), 1)
        XCTAssertEqual(try count(CalendarEvent.self), 1)
        XCTAssertEqual(try count(Holiday.self), 1)

        let restoredSubject = try XCTUnwrap(context.fetch(FetchDescriptor<SchoolSubject>()).first)
        XCTAssertEqual(restoredSubject.uid, math.uid)
        XCTAssertEqual(restoredSubject.teacher, "Frau Schmidt")
        XCTAssertEqual(restoredSubject.lessons?.first?.room, "204")
        XCTAssertEqual(restoredSubject.rootTopics.map(\.title), ["Analysis"])
        XCTAssertEqual(restoredSubject.rootTopics.first?.sortedChildren.map(\.title), ["Ableitungen"])

        let restoredTask = try XCTUnwrap(context.fetch(FetchDescriptor<SchoolTask>()).first)
        XCTAssertEqual(restoredTask.subject?.name, "Mathematik")
        XCTAssertEqual(restoredTask.topic?.title, "Ableitungen")
        XCTAssertEqual(restoredTask.exam?.displayTitle, "Klassenarbeit Mathematik")
        XCTAssertEqual(restoredTask.sortedSubtasks.map(\.isDone), [true])

        let restoredEvent = try XCTUnwrap(context.fetch(FetchDescriptor<CalendarEvent>()).first)
        XCTAssertEqual(restoredEvent.recurrence, .weekly)
        XCTAssertEqual(restoredEvent.category, .school)
    }

    func testDecodeRejectsOtherFiles() {
        XCTAssertThrowsError(try BackupService.decode(Data("{\"hello\": 1}".utf8)))
        XCTAssertThrowsError(try BackupService.decode(Data("not json".utf8)))
    }
}
