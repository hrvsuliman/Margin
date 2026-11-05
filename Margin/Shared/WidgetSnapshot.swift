import Foundation

/// What the home-screen widgets show, written by the app into the shared App Group folder.
/// Shared by the app and the widget extension, so it only uses Foundation.
struct WidgetSnapshot: Codable, Equatable {
    struct Lesson: Codable, Equatable {
        var start: Date
        var end: Date
        var subject: String
        var room: String
        var colorKey: String
        var cancelled: Bool
        var changed: Bool
        var subjectID: UUID?
    }

    struct Task: Codable, Equatable {
        var id: UUID
        var title: String
        var subject: String
        var colorKey: String
        var due: Date?
    }

    struct Exam: Codable, Equatable {
        var id: UUID
        var title: String
        var subject: String
        var colorKey: String
        var date: Date
        var readiness: Double
    }

    var generatedAt = Date.now
    var lessons: [Lesson] = []
    var tasks: [Task] = []
    var exams: [Exam] = []

    static let appGroup = "group.com.hrvsuliman.margin"
    private static let fileName = "widget-snapshot.json"

    /// Nil when the App Group isn't available (e.g. not granted when sideloading).
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    // MARK: Questions the widgets ask

    /// The lesson running at `date`, or else the next one (cancelled lessons skipped).
    func currentOrNextLesson(at date: Date) -> Lesson? {
        let open = lessons.filter { !$0.cancelled && $0.end > date }.sorted { $0.start < $1.start }
        return open.first
    }

    /// The lessons after `lesson` on the same day.
    func laterLessons(after lesson: Lesson, calendar: Calendar = .current) -> [Lesson] {
        lessons.filter { $0.start > lesson.start && calendar.isDate($0.start, inSameDayAs: lesson.start) }
            .sorted { $0.start < $1.start }
    }

    func openTasks(at date: Date) -> [Task] {
        tasks.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func nextExam(at date: Date, calendar: Calendar = .current) -> Exam? {
        exams.filter { $0.date >= calendar.startOfDay(for: date) }.min { $0.date < $1.date }
    }

    /// Times at which a widget should redraw: every lesson start and end in the next day.
    func refreshDates(after date: Date) -> [Date] {
        let limit = date.addingTimeInterval(24 * 60 * 60)
        let times = lessons.flatMap { [$0.start, $0.end] }.filter { $0 > date && $0 < limit }
        return Array(Set(times)).sorted().prefix(30).map { $0 }
    }
}
