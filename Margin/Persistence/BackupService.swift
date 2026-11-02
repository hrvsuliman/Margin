import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Everything in Margin as one JSON file, including attachment files.
/// Relationships are stored as `uid` references.
struct BackupFile: Codable {
    static let formatName = "margin-backup"

    var format: String = BackupFile.formatName
    var version: Int = 1
    var exportedAt: Date = .now
    var appVersion: String = ""
    var settings: SettingsSnapshot?
    var subjects: [SubjectDTO] = []
    var topics: [TopicDTO] = []
    var lessons: [LessonDTO] = []
    var tasks: [TaskDTO] = []
    var subtasks: [SubtaskDTO] = []
    var exams: [ExamDTO] = []
    var events: [EventDTO] = []
    var attachments: [AttachmentDTO] = []
    var holidays: [HolidayDTO] = []

    struct SubjectDTO: Codable {
        var uid: UUID; var name: String; var colorKey: String; var teacher: String; var room: String
        var notes: String; var sortIndex: Int; var createdAt: Date
    }
    struct TopicDTO: Codable {
        var uid: UUID; var title: String; var details: String; var sortIndex: Int; var createdAt: Date
        var subject: UUID?; var parent: UUID?
    }
    struct LessonDTO: Codable {
        var uid: UUID; var weekday: Int; var startMinute: Int; var endMinute: Int; var room: String
        var note: String; var subject: UUID?
    }
    struct TaskDTO: Codable {
        var uid: UUID; var title: String; var details: String; var kind: String; var priority: Int
        var status: String; var dueDate: Date?; var hasDueTime: Bool; var reminderDate: Date?
        var estimatedMinutes: Int; var createdAt: Date; var completedAt: Date?
        var subject: UUID?; var topic: UUID?; var exam: UUID?
    }
    struct SubtaskDTO: Codable {
        var uid: UUID; var title: String; var isDone: Bool; var sortIndex: Int; var task: UUID?
    }
    struct ExamDTO: Codable {
        var uid: UUID; var title: String; var kind: String; var date: Date; var hasTime: Bool
        var durationMinutes: Int; var room: String; var notes: String; var reminderDaysBefore: Int
        var createdAt: Date; var subject: UUID?
    }
    struct EventDTO: Codable {
        var uid: UUID; var title: String; var notes: String; var location: String; var start: Date; var end: Date
        var isAllDay: Bool; var category: String; var recurrence: String; var recurrenceEnd: Date?
        var reminderMinutesBefore: Int; var createdAt: Date; var subject: UUID?
    }
    struct AttachmentDTO: Codable {
        var uid: UUID; var fileName: String; var createdAt: Date; var data: Data
        var task: UUID?; var subject: UUID?
    }
    struct HolidayDTO: Codable {
        var uid: UUID; var name: String; var start: Date; var end: Date
    }
}

enum BackupError: LocalizedError {
    case notABackup
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .notABackup: "Diese Datei ist kein Margin-Backup."
        case .newerVersion: "Dieses Backup stammt aus einer neueren Margin-Version. Bitte aktualisiere die App zuerst."
        }
    }
}

@MainActor
enum BackupService {
    private static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func suggestedFileName(now: Date = .now) -> String {
        let parts = Calendar.school.dateComponents([.year, .month, .day], from: now)
        return String(format: "Margin-Backup-%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func export(context: ModelContext, settings: AppSettings?) throws -> Data {
        var file = BackupFile()
        file.appVersion = BuildInfo.current.displayVersion
        file.settings = settings.map { SettingsSnapshot($0) }

        file.subjects = all(SchoolSubject.self, context).map {
            BackupFile.SubjectDTO(uid: $0.uid, name: $0.name, colorKey: $0.colorKey, teacher: $0.teacher, room: $0.room,
                  notes: $0.notes, sortIndex: $0.sortIndex, createdAt: $0.createdAt)
        }
        file.topics = all(Topic.self, context).map {
            BackupFile.TopicDTO(uid: $0.uid, title: $0.title, details: $0.details, sortIndex: $0.sortIndex, createdAt: $0.createdAt,
                  subject: $0.subject?.uid, parent: $0.parent?.uid)
        }
        file.lessons = all(Lesson.self, context).map {
            BackupFile.LessonDTO(uid: $0.uid, weekday: $0.weekday, startMinute: $0.startMinute, endMinute: $0.endMinute,
                  room: $0.room, note: $0.note, subject: $0.subject?.uid)
        }
        file.tasks = all(SchoolTask.self, context).map {
            BackupFile.TaskDTO(uid: $0.uid, title: $0.title, details: $0.details, kind: $0.kindRaw, priority: $0.priorityRaw,
                  status: $0.statusRaw, dueDate: $0.dueDate, hasDueTime: $0.hasDueTime, reminderDate: $0.reminderDate,
                  estimatedMinutes: $0.estimatedMinutes, createdAt: $0.createdAt, completedAt: $0.completedAt,
                  subject: $0.subject?.uid, topic: $0.topic?.uid, exam: $0.exam?.uid)
        }
        file.subtasks = all(Subtask.self, context).map {
            BackupFile.SubtaskDTO(uid: $0.uid, title: $0.title, isDone: $0.isDone, sortIndex: $0.sortIndex, task: $0.task?.uid)
        }
        file.exams = all(Exam.self, context).map {
            BackupFile.ExamDTO(uid: $0.uid, title: $0.title, kind: $0.kindRaw, date: $0.date, hasTime: $0.hasTime,
                  durationMinutes: $0.durationMinutes, room: $0.room, notes: $0.notes,
                  reminderDaysBefore: $0.reminderDaysBefore, createdAt: $0.createdAt, subject: $0.subject?.uid)
        }
        file.events = all(CalendarEvent.self, context).map {
            BackupFile.EventDTO(uid: $0.uid, title: $0.title, notes: $0.notes, location: $0.location, start: $0.start, end: $0.end,
                  isAllDay: $0.isAllDay, category: $0.categoryRaw, recurrence: $0.recurrenceRaw,
                  recurrenceEnd: $0.recurrenceEnd, reminderMinutesBefore: $0.reminderMinutesBefore,
                  createdAt: $0.createdAt, subject: $0.subject?.uid)
        }
        file.attachments = all(Attachment.self, context).compactMap { attachment in
            guard let data = AttachmentStore.data(for: attachment) else { return nil as BackupFile.AttachmentDTO? }
            return BackupFile.AttachmentDTO(uid: attachment.uid, fileName: attachment.fileName, createdAt: attachment.createdAt,
                         data: data, task: attachment.task?.uid, subject: attachment.subject?.uid)
        }
        file.holidays = all(Holiday.self, context).map {
            BackupFile.HolidayDTO(uid: $0.uid, name: $0.name, start: $0.start, end: $0.end)
        }

        return try encoder.encode(file)
    }

    /// Reads and checks a backup without changing anything.
    static func decode(_ data: Data) throws -> BackupFile {
        guard let file = try? decoder.decode(BackupFile.self, from: data),
              file.format == BackupFile.formatName else {
            throw BackupError.notABackup
        }
        guard file.version <= 1 else { throw BackupError.newerVersion }
        return file
    }

    /// Replaces all data with the backup.
    static func restore(_ file: BackupFile, context: ModelContext, settings: AppSettings?) throws {
        deleteEverything(context: context)

        var subjects: [UUID: SchoolSubject] = [:]
        for dto in file.subjects {
            let subject = SchoolSubject(name: dto.name, colorKey: dto.colorKey, sortIndex: dto.sortIndex)
            subject.uid = dto.uid
            subject.teacher = dto.teacher
            subject.room = dto.room
            subject.notes = dto.notes
            subject.createdAt = dto.createdAt
            context.insert(subject)
            subjects[dto.uid] = subject
        }

        var topics: [UUID: Topic] = [:]
        for dto in file.topics {
            let topic = Topic(title: dto.title, subject: nil, sortIndex: dto.sortIndex)
            topic.uid = dto.uid
            topic.details = dto.details
            topic.createdAt = dto.createdAt
            context.insert(topic)
            topic.subject = dto.subject.flatMap { subjects[$0] }
            topics[dto.uid] = topic
        }
        for dto in file.topics {
            topics[dto.uid]?.parent = dto.parent.flatMap { topics[$0] }
        }

        for dto in file.lessons {
            let lesson = Lesson(subject: nil, weekday: dto.weekday, startMinute: dto.startMinute,
                                endMinute: dto.endMinute, room: dto.room)
            lesson.uid = dto.uid
            lesson.note = dto.note
            context.insert(lesson)
            lesson.subject = dto.subject.flatMap { subjects[$0] }
        }

        var exams: [UUID: Exam] = [:]
        for dto in file.exams {
            let exam = Exam(title: dto.title, kind: ExamKind(rawValue: dto.kind) ?? .other, date: dto.date, subject: nil)
            exam.uid = dto.uid
            exam.hasTime = dto.hasTime
            exam.durationMinutes = dto.durationMinutes
            exam.room = dto.room
            exam.notes = dto.notes
            exam.reminderDaysBefore = dto.reminderDaysBefore
            exam.createdAt = dto.createdAt
            context.insert(exam)
            exam.subject = dto.subject.flatMap { subjects[$0] }
            exams[dto.uid] = exam
        }

        var tasks: [UUID: SchoolTask] = [:]
        for dto in file.tasks {
            let task = SchoolTask(title: dto.title)
            task.uid = dto.uid
            task.details = dto.details
            task.kindRaw = dto.kind
            task.priorityRaw = dto.priority
            task.statusRaw = dto.status
            task.dueDate = dto.dueDate
            task.hasDueTime = dto.hasDueTime
            task.reminderDate = dto.reminderDate
            task.estimatedMinutes = dto.estimatedMinutes
            task.createdAt = dto.createdAt
            task.completedAt = dto.completedAt
            context.insert(task)
            task.subject = dto.subject.flatMap { subjects[$0] }
            task.topic = dto.topic.flatMap { topics[$0] }
            task.exam = dto.exam.flatMap { exams[$0] }
            tasks[dto.uid] = task
        }

        for dto in file.subtasks {
            let subtask = Subtask(title: dto.title, sortIndex: dto.sortIndex, isDone: dto.isDone)
            subtask.uid = dto.uid
            context.insert(subtask)
            subtask.task = dto.task.flatMap { tasks[$0] }
        }

        for dto in file.events {
            let event = CalendarEvent(title: dto.title, start: dto.start, end: dto.end,
                                      category: EventCategory(rawValue: dto.category) ?? .other)
            event.uid = dto.uid
            event.notes = dto.notes
            event.location = dto.location
            event.isAllDay = dto.isAllDay
            event.recurrenceRaw = dto.recurrence
            event.recurrenceEnd = dto.recurrenceEnd
            event.reminderMinutesBefore = dto.reminderMinutesBefore
            event.createdAt = dto.createdAt
            context.insert(event)
            event.subject = dto.subject.flatMap { subjects[$0] }
        }

        for dto in file.attachments {
            let attachment = try AttachmentStore.store(dto.data, fileName: dto.fileName)
            attachment.uid = dto.uid
            attachment.createdAt = dto.createdAt
            context.insert(attachment)
            attachment.task = dto.task.flatMap { tasks[$0] }
            attachment.subject = dto.subject.flatMap { subjects[$0] }
        }

        for dto in file.holidays {
            let holiday = Holiday(name: dto.name, start: dto.start, end: dto.end)
            holiday.uid = dto.uid
            context.insert(holiday)
        }

        if let settings, let snapshot = file.settings {
            snapshot.apply(to: settings)
        }
        context.commit()
    }

    /// Deletes all school data and attachment files. Settings stay.
    static func deleteEverything(context: ModelContext) {
        all(Subtask.self, context).forEach { context.delete($0) }
        all(Attachment.self, context).forEach { context.delete($0) }
        all(Lesson.self, context).forEach { context.delete($0) }
        all(SchoolTask.self, context).forEach { context.delete($0) }
        all(Topic.self, context).forEach { context.delete($0) }
        all(Exam.self, context).forEach { context.delete($0) }
        all(CalendarEvent.self, context).forEach { context.delete($0) }
        all(Holiday.self, context).forEach { context.delete($0) }
        all(SchoolSubject.self, context).forEach { context.delete($0) }
        try? context.save()
        AttachmentStore.removeAllFiles()
    }
}

/// Wraps backup data for the system "Save to Files" dialog.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
