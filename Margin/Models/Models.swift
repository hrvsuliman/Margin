import Foundation
import SwiftData

// All model properties have default values and all relationships are optional.
// That's required for a future iCloud sync and keeps schema migrations simple.
// `uid` is a stable identifier used by backups and notifications.

@Model
final class SchoolSubject {
    var uid: UUID = UUID()
    var name: String = ""
    var colorKey: String = SubjectColor.blue.rawValue
    var teacher: String = ""
    var room: String = ""
    var notes: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Lesson.subject)
    var lessons: [Lesson]? = []
    @Relationship(deleteRule: .cascade, inverse: \Topic.subject)
    var topics: [Topic]? = []
    @Relationship(deleteRule: .nullify, inverse: \SchoolTask.subject)
    var tasks: [SchoolTask]? = []
    @Relationship(deleteRule: .nullify, inverse: \Exam.subject)
    var exams: [Exam]? = []
    @Relationship(deleteRule: .nullify, inverse: \CalendarEvent.subject)
    var events: [CalendarEvent]? = []
    @Relationship(deleteRule: .cascade, inverse: \Attachment.subject)
    var attachments: [Attachment]? = []

    init(name: String, colorKey: String, sortIndex: Int = 0) {
        self.uid = UUID()
        self.name = name
        self.colorKey = colorKey
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    var color: SubjectColor { SubjectColor(rawValue: colorKey) ?? .gray }

    /// Top-level topics in their manual order.
    var rootTopics: [Topic] {
        (topics ?? []).filter { $0.parent == nil }.sorted { $0.sortIndex < $1.sortIndex }
    }

    var sortedLessons: [Lesson] {
        (lessons ?? []).sorted { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }
    }
}

/// A learning topic inside a subject. Topics can contain subtopics.
@Model
final class Topic {
    var uid: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    var subject: SchoolSubject?
    var parent: Topic?
    @Relationship(deleteRule: .cascade, inverse: \Topic.parent)
    var children: [Topic]? = []
    @Relationship(deleteRule: .nullify, inverse: \SchoolTask.topic)
    var tasks: [SchoolTask]? = []

    init(title: String, subject: SchoolSubject?, parent: Topic? = nil, sortIndex: Int = 0) {
        self.uid = UUID()
        self.title = title
        self.subject = subject
        self.parent = parent
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    var sortedChildren: [Topic] {
        (children ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// A weekly timetable slot, e.g. Mathe every Monday 08:00–09:30.
@Model
final class Lesson {
    var uid: UUID = UUID()
    /// 1 = Monday … 7 = Sunday.
    var weekday: Int = 1
    /// Minutes since midnight.
    var startMinute: Int = 480
    var endMinute: Int = 525
    var room: String = ""
    var note: String = ""

    var subject: SchoolSubject?

    init(subject: SchoolSubject?, weekday: Int, startMinute: Int, endMinute: Int, room: String = "") {
        self.uid = UUID()
        self.subject = subject
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.room = room
    }
}

@Model
final class SchoolTask {
    var uid: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var kindRaw: String = TaskKind.homework.rawValue
    var priorityRaw: Int = TaskPriority.normal.rawValue
    var statusRaw: String = TaskStatus.open.rawValue
    /// The day it's due. If `hasDueTime` is false only the day matters.
    var dueDate: Date?
    var hasDueTime: Bool = false
    /// An explicit reminder. If nil, the default reminder from Settings applies.
    var reminderDate: Date?
    var estimatedMinutes: Int = 0
    var createdAt: Date = Date.now
    var completedAt: Date?

    var subject: SchoolSubject?
    var topic: Topic?
    var exam: Exam?
    @Relationship(deleteRule: .cascade, inverse: \Subtask.task)
    var subtasks: [Subtask]? = []
    @Relationship(deleteRule: .cascade, inverse: \Attachment.task)
    var attachments: [Attachment]? = []

    init(title: String, kind: TaskKind = .homework, subject: SchoolSubject? = nil, dueDate: Date? = nil) {
        self.uid = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.subject = subject
        self.dueDate = dueDate
        self.createdAt = .now
    }

    var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw) ?? .general }
        set { kindRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .open }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? .now) : nil
        }
    }

    var isDone: Bool { status == .done }

    var sortedSubtasks: [Subtask] {
        (subtasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The moment after which the task counts as overdue.
    var deadline: Date? {
        guard let dueDate else { return nil }
        if hasDueTime { return dueDate }
        let calendar = Calendar.school
        return calendar.addingDays(1, to: calendar.startOfDay(for: dueDate))
    }

    func isOverdue(now: Date = .now) -> Bool {
        guard !isDone, let deadline else { return false }
        return deadline <= now
    }
}

@Model
final class Subtask {
    var uid: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var sortIndex: Int = 0

    var task: SchoolTask?

    init(title: String, sortIndex: Int, isDone: Bool = false) {
        self.uid = UUID()
        self.title = title
        self.sortIndex = sortIndex
        self.isDone = isDone
    }
}

/// A written or oral exam. Phase 3 adds topics, understanding and a learning roadmap.
@Model
final class Exam {
    var uid: UUID = UUID()
    var title: String = ""
    var kindRaw: String = ExamKind.classTest.rawValue
    var date: Date = Date.now
    var hasTime: Bool = false
    var durationMinutes: Int = 90
    var room: String = ""
    var notes: String = ""
    /// Days before the exam to send a reminder (at 17:00). -1 = no reminder.
    var reminderDaysBefore: Int = 1
    var createdAt: Date = Date.now

    var subject: SchoolSubject?
    @Relationship(deleteRule: .nullify, inverse: \SchoolTask.exam)
    var tasks: [SchoolTask]? = []

    init(title: String, kind: ExamKind, date: Date, subject: SchoolSubject?) {
        self.uid = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.date = date
        self.subject = subject
        self.createdAt = .now
    }

    var kind: ExamKind {
        get { ExamKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    /// "Klassenarbeit Mathe" if no own title was given.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return [kind.title, subject?.name].compactMap { $0 }.joined(separator: " ")
    }
}

@Model
final class CalendarEvent {
    var uid: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var location: String = ""
    var start: Date = Date.now
    /// For all-day events: the start of the last day (inclusive).
    var end: Date = Date.now
    var isAllDay: Bool = false
    var categoryRaw: String = EventCategory.personal.rawValue
    var recurrenceRaw: String = Recurrence.never.rawValue
    var recurrenceEnd: Date?
    /// Minutes before the start to remind. -1 = no reminder.
    var reminderMinutesBefore: Int = -1
    var createdAt: Date = Date.now

    var subject: SchoolSubject?

    init(title: String, start: Date, end: Date, category: EventCategory) {
        self.uid = UUID()
        self.title = title
        self.start = start
        self.end = end
        self.categoryRaw = category.rawValue
        self.createdAt = .now
    }

    var category: EventCategory {
        get { EventCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .never }
        set { recurrenceRaw = newValue.rawValue }
    }
}

/// A file (PDF, photo, document) copied into the app. The file itself lives in
/// Application Support/Attachments; see `AttachmentStore`.
@Model
final class Attachment {
    var uid: UUID = UUID()
    /// The original file name shown to the user.
    var fileName: String = ""
    /// The name of the copy on disk.
    var storedName: String = ""
    var byteCount: Int = 0
    var createdAt: Date = Date.now

    var task: SchoolTask?
    var subject: SchoolSubject?

    init(fileName: String, storedName: String, byteCount: Int) {
        self.uid = UUID()
        self.fileName = fileName
        self.storedName = storedName
        self.byteCount = byteCount
        self.createdAt = .now
    }
}

/// School holidays or other days without lessons. Both days are inclusive.
@Model
final class Holiday {
    var uid: UUID = UUID()
    var name: String = ""
    var start: Date = Date.now
    var end: Date = Date.now

    init(name: String, start: Date, end: Date) {
        self.uid = UUID()
        self.name = name
        self.start = start
        self.end = end
    }

    func contains(_ day: Date, calendar: Calendar = .school) -> Bool {
        let d = calendar.startOfDay(for: day)
        return calendar.startOfDay(for: start) <= d && d <= calendar.startOfDay(for: end)
    }
}
