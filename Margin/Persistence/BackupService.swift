import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Everything in Margin as one JSON file, including attachment files.
/// Relationships are stored as `uid` references.
struct BackupFile: Codable {
    static let formatName = "margin-backup"

    var format: String = BackupFile.formatName
    /// 1 = Phase 1, 2 = adds handwriting and notes, 3 = learning, grades, note images,
    /// 4 = note pages/pins and lesson recordings, 5 = subject pinboards.
    var version: Int = 5
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
    // Optional so that version 1 backups (without them) still load.
    var profiles: [ProfileDTO]?
    var glyphs: [GlyphDTO]?
    var notes: [NoteDTO]?
    var learning: LearningDTO?
    var chats: [ChatDTO]?
    var noteMeta: [NoteMetaDTO]?
    var recordings: [RecordingDTO]?
    var pins: [PinDTO]?

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
    struct ProfileDTO: Codable {
        var uid: UUID; var name: String; var isDefault: Bool; var createdAt: Date
        var letterSpacing: Double; var wordSpacing: Double; var slantAdjust: Double; var variation: Double
        var spacingMeasured: Bool
    }
    struct GlyphDTO: Codable {
        var uid: UUID; var character: String; var strokes: Data; var createdAt: Date
        var scale: Double; var baselineOffset: Double; var profile: UUID?
    }
    /// Phase 3 data. Models are encoded as-is (they only hold plain values and ids).
    struct LearningDTO: Codable {
        var progress: [ProgressDTO] = []
        var events: [EventLogDTO] = []
        var plans: [PlanDTO] = []
        var sessions: [SessionDTO] = []
        var cards: [CardDTO] = []
        var results: [ResultDTO] = []
        var grades: [GradeDTO] = []
        var gradeSetups: [GradeSetupDTO] = []
        var images: [NoteImageDTO] = []
    }
    struct ProgressDTO: Codable {
        var uid: UUID; var topic: UUID?; var understanding: Int; var completion: Double; var importance: Int
        var estimatedMinutes: Int; var lastStudied: Date?; var updatedAt: Date
    }
    struct EventLogDTO: Codable { var uid: UUID; var topic: UUID?; var level: Int; var date: Date; var source: String }
    struct PlanDTO: Codable {
        var uid: UUID; var exam: UUID?; var topics: [UUID]; var dailyMinutes: Int; var weekdays: [Int]
        var generatedAt: Date?; var createdAt: Date
    }
    struct SessionDTO: Codable {
        var uid: UUID; var exam: UUID?; var topic: UUID?; var subject: UUID?; var kind: String; var status: String
        var date: Date; var plannedMinutes: Int; var actualMinutes: Int; var completedAt: Date?; var isPlanned: Bool; var note: String
    }
    struct CardDTO: Codable {
        var uid: UUID; var subject: UUID?; var topic: UUID?; var note: UUID?; var front: String; var back: String
        var createdAt: Date; var ease: Double; var intervalDays: Int; var repetitions: Int; var lapses: Int
        var due: Date; var lastReviewed: Date?
    }
    struct ResultDTO: Codable {
        var uid: UUID; var topic: UUID?; var exam: UUID?; var subject: UUID?; var score: Double; var date: Date; var kind: String
    }
    struct GradeDTO: Codable {
        var uid: UUID; var subject: UUID?; var exam: UUID?; var title: String; var value: Double; var kind: String
        var weight: Double; var date: Date
    }
    struct GradeSetupDTO: Codable { var uid: UUID; var subject: UUID?; var writtenShare: Double; var goal: Double? }
    struct NoteImageDTO: Codable {
        var uid: UUID; var note: UUID?; var caption: String; var heightLines: Int; var createdAt: Date; var data: Data
    }

    struct ChatDTO: Codable {
        var uid: UUID; var title: String; var engine: String; var createdAt: Date; var updatedAt: Date
        var items: Data; var messages: Data
    }

    struct NoteMetaDTO: Codable {
        var uid: UUID; var note: UUID?; var parent: UUID?; var pinned: Bool; var template: String
    }
    struct PinDTO: Codable {
        var uid: UUID; var subject: UUID?; var kind: String; var title: String; var text: String; var url: String
        var note: UUID?; var color: String; var sortIndex: Int; var createdAt: Date; var photo: Data?
    }
    struct RecordingDTO: Codable {
        var uid: UUID; var note: UUID?; var duration: Double; var createdAt: Date; var data: Data
    }

    struct NoteDTO: Codable {
        var uid: UUID; var title: String; var body: String; var folder: String; var noteDate: Date
        var createdAt: Date; var updatedAt: Date
        var subject: UUID?; var topic: UUID?; var exam: UUID?; var profile: UUID?
        var paper: String; var lineSpacingMM: Double; var writingSize: Double; var penColor: String; var penWeight: Double
        var marginTopMM: Double; var marginBottomMM: Double; var marginLeftMM: Double; var marginRightMM: Double
        var showMarginLine: Bool; var showPageNumbers: Bool; var showHeader: Bool; var printPaper: Bool; var seed: Int
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
    static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
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
        file.profiles = all(HandwritingProfile.self, context).map {
            BackupFile.ProfileDTO(uid: $0.uid, name: $0.name, isDefault: $0.isDefault, createdAt: $0.createdAt,
                                  letterSpacing: $0.letterSpacing, wordSpacing: $0.wordSpacing,
                                  slantAdjust: $0.slantAdjust, variation: $0.variation, spacingMeasured: $0.spacingMeasured)
        }
        file.glyphs = all(GlyphSample.self, context).map {
            BackupFile.GlyphDTO(uid: $0.uid, character: $0.character, strokes: $0.strokeData, createdAt: $0.createdAt,
                                scale: $0.scale, baselineOffset: $0.baselineOffset, profile: $0.profile?.uid)
        }
        file.learning = exportLearning(context)
        file.chats = all(ChatThread.self, context).map {
            BackupFile.ChatDTO(uid: $0.uid, title: $0.title, engine: $0.engineRaw, createdAt: $0.createdAt,
                               updatedAt: $0.updatedAt, items: $0.itemsData, messages: $0.messagesData)
        }
        file.noteMeta = all(NoteMeta.self, context).map {
            BackupFile.NoteMetaDTO(uid: $0.uid, note: $0.noteUID, parent: $0.parentUID, pinned: $0.pinned, template: $0.template)
        }
        file.recordings = all(NoteAudio.self, context).compactMap { audio in
            guard let data = try? Data(contentsOf: AttachmentStore.directory.appendingPathComponent(audio.storedName)) else {
                return nil as BackupFile.RecordingDTO?
            }
            return BackupFile.RecordingDTO(uid: audio.uid, note: audio.noteUID, duration: audio.duration,
                                           createdAt: audio.createdAt, data: data)
        }
        file.pins = all(PinItem.self, context).map { pin in
            let photo = pin.storedName.isEmpty ? nil
                : try? Data(contentsOf: AttachmentStore.directory.appendingPathComponent(pin.storedName))
            return BackupFile.PinDTO(uid: pin.uid, subject: pin.subjectUID, kind: pin.kindRaw, title: pin.title, text: pin.text,
                                     url: pin.urlString, note: pin.noteUID, color: pin.colorKey, sortIndex: pin.sortIndex,
                                     createdAt: pin.createdAt, photo: photo)
        }
        file.notes = all(NoteDocument.self, context).map { note in
            BackupFile.NoteDTO(
                uid: note.uid, title: note.title, body: note.body, folder: note.folder, noteDate: note.noteDate,
                createdAt: note.createdAt, updatedAt: note.updatedAt,
                subject: note.subjectUID, topic: note.topicUID, exam: note.examUID, profile: note.profileUID,
                paper: note.paperRaw, lineSpacingMM: note.lineSpacingMM, writingSize: note.writingSize,
                penColor: note.penColorRaw, penWeight: note.penWeight,
                marginTopMM: note.marginTopMM, marginBottomMM: note.marginBottomMM,
                marginLeftMM: note.marginLeftMM, marginRightMM: note.marginRightMM,
                showMarginLine: note.showMarginLine, showPageNumbers: note.showPageNumbers,
                showHeader: note.showHeader, printPaper: note.printPaper, seed: note.seed
            )
        }

        return try encoder.encode(file)
    }

    /// Reads and checks a backup without changing anything.
    static func decode(_ data: Data) throws -> BackupFile {
        guard let file = try? decoder.decode(BackupFile.self, from: data),
              file.format == BackupFile.formatName else {
            throw BackupError.notABackup
        }
        guard file.version <= 5 else { throw BackupError.newerVersion }
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

        var profiles: [UUID: HandwritingProfile] = [:]
        for dto in file.profiles ?? [] {
            let profile = HandwritingProfile(name: dto.name)
            profile.uid = dto.uid
            profile.isDefault = dto.isDefault
            profile.createdAt = dto.createdAt
            profile.letterSpacing = dto.letterSpacing
            profile.wordSpacing = dto.wordSpacing
            profile.slantAdjust = dto.slantAdjust
            profile.variation = dto.variation
            profile.spacingMeasured = dto.spacingMeasured
            context.insert(profile)
            profiles[dto.uid] = profile
        }

        for dto in file.glyphs ?? [] {
            let glyph = GlyphSample(character: dto.character, strokeData: dto.strokes)
            glyph.uid = dto.uid
            glyph.createdAt = dto.createdAt
            glyph.scale = dto.scale
            glyph.baselineOffset = dto.baselineOffset
            context.insert(glyph)
            glyph.profile = dto.profile.flatMap { profiles[$0] }
        }

        for dto in file.notes ?? [] {
            let note = NoteDocument(title: dto.title)
            note.uid = dto.uid
            note.body = dto.body
            note.folder = dto.folder
            note.noteDate = dto.noteDate
            note.createdAt = dto.createdAt
            note.updatedAt = dto.updatedAt
            note.subjectUID = dto.subject
            note.topicUID = dto.topic
            note.examUID = dto.exam
            note.profileUID = dto.profile
            note.paperRaw = dto.paper
            note.lineSpacingMM = dto.lineSpacingMM
            note.writingSize = dto.writingSize
            note.penColorRaw = dto.penColor
            note.penWeight = dto.penWeight
            note.marginTopMM = dto.marginTopMM
            note.marginBottomMM = dto.marginBottomMM
            note.marginLeftMM = dto.marginLeftMM
            note.marginRightMM = dto.marginRightMM
            note.showMarginLine = dto.showMarginLine
            note.showPageNumbers = dto.showPageNumbers
            note.showHeader = dto.showHeader
            note.printPaper = dto.printPaper
            note.seed = dto.seed
            context.insert(note)
        }

        if let learning = file.learning {
            try restoreLearning(learning, context: context)
        }
        for dto in file.chats ?? [] {
            let thread = ChatThread(engine: TutorEngine(rawValue: dto.engine) ?? .claudeAPI)
            thread.uid = dto.uid
            thread.title = dto.title
            thread.createdAt = dto.createdAt
            thread.updatedAt = dto.updatedAt
            thread.itemsData = dto.items
            thread.messagesData = dto.messages
            context.insert(thread)
        }
        for dto in file.noteMeta ?? [] {
            let meta = NoteMeta(noteUID: dto.note ?? UUID())
            meta.uid = dto.uid
            meta.noteUID = dto.note
            meta.parentUID = dto.parent
            meta.pinned = dto.pinned
            meta.template = dto.template
            context.insert(meta)
        }
        for dto in file.pins ?? [] {
            let pin = PinItem(subjectUID: dto.subject, kind: PinKind(rawValue: dto.kind) ?? .sticky)
            pin.uid = dto.uid
            pin.title = dto.title
            pin.text = dto.text
            pin.urlString = dto.url
            pin.noteUID = dto.note
            pin.colorKey = dto.color
            pin.sortIndex = dto.sortIndex
            pin.createdAt = dto.createdAt
            if let photo = dto.photo {
                pin.storedName = try AttachmentStore.store(photo, fileName: "pin.jpg").storedName
            }
            context.insert(pin)
        }
        for dto in file.recordings ?? [] {
            let stored = try AttachmentStore.store(dto.data, fileName: "aufnahme.m4a")
            let audio = NoteAudio(noteUID: dto.note ?? UUID(), storedName: stored.storedName, duration: dto.duration)
            audio.uid = dto.uid
            audio.noteUID = dto.note
            audio.createdAt = dto.createdAt
            context.insert(audio)
        }

        if let settings, let snapshot = file.settings {
            snapshot.apply(to: settings)
        }
        context.commit()
    }

    /// Deletes all school data, notes, handwriting and attachment files. Settings stay.
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
        all(GlyphSample.self, context).forEach { context.delete($0) }
        all(HandwritingProfile.self, context).forEach { context.delete($0) }
        all(NoteDocument.self, context).forEach { context.delete($0) }
        all(TopicProgress.self, context).forEach { context.delete($0) }
        all(UnderstandingEvent.self, context).forEach { context.delete($0) }
        all(ExamPlan.self, context).forEach { context.delete($0) }
        all(StudySession.self, context).forEach { context.delete($0) }
        all(Flashcard.self, context).forEach { context.delete($0) }
        all(PracticeResult.self, context).forEach { context.delete($0) }
        all(Grade.self, context).forEach { context.delete($0) }
        all(GradeSetup.self, context).forEach { context.delete($0) }
        all(NoteImage.self, context).forEach { context.delete($0) }
        all(ChatThread.self, context).forEach { context.delete($0) }
        all(NoteMeta.self, context).forEach { context.delete($0) }
        all(NoteAudio.self, context).forEach { context.delete($0) }
        all(TimetableEntry.self, context).forEach { context.delete($0) }
        all(PinItem.self, context).forEach { context.delete($0) }
        try? context.save()
        AttachmentStore.removeAllFiles()
    }
}

extension BackupService {
    static func exportLearning(_ context: ModelContext) -> BackupFile.LearningDTO {
        var dto = BackupFile.LearningDTO()
        dto.progress = all(TopicProgress.self, context).map {
            BackupFile.ProgressDTO(uid: $0.uid, topic: $0.topicUID, understanding: $0.understandingRaw, completion: $0.completion,
                                   importance: $0.importance, estimatedMinutes: $0.estimatedMinutes,
                                   lastStudied: $0.lastStudied, updatedAt: $0.updatedAt)
        }
        dto.events = all(UnderstandingEvent.self, context).map {
            BackupFile.EventLogDTO(uid: $0.uid, topic: $0.topicUID, level: $0.level, date: $0.date, source: $0.source)
        }
        dto.plans = all(ExamPlan.self, context).map {
            BackupFile.PlanDTO(uid: $0.uid, exam: $0.examUID, topics: $0.topicUIDs, dailyMinutes: $0.dailyMinutes,
                               weekdays: $0.studyWeekdays, generatedAt: $0.generatedAt, createdAt: $0.createdAt)
        }
        dto.sessions = all(StudySession.self, context).map {
            BackupFile.SessionDTO(uid: $0.uid, exam: $0.examUID, topic: $0.topicUID, subject: $0.subjectUID, kind: $0.kindRaw,
                                  status: $0.statusRaw, date: $0.date, plannedMinutes: $0.plannedMinutes,
                                  actualMinutes: $0.actualMinutes, completedAt: $0.completedAt, isPlanned: $0.isPlanned, note: $0.note)
        }
        dto.cards = all(Flashcard.self, context).map {
            BackupFile.CardDTO(uid: $0.uid, subject: $0.subjectUID, topic: $0.topicUID, note: $0.noteUID, front: $0.front,
                               back: $0.back, createdAt: $0.createdAt, ease: $0.ease, intervalDays: $0.intervalDays,
                               repetitions: $0.repetitions, lapses: $0.lapses, due: $0.due, lastReviewed: $0.lastReviewed)
        }
        dto.results = all(PracticeResult.self, context).map {
            BackupFile.ResultDTO(uid: $0.uid, topic: $0.topicUID, exam: $0.examUID, subject: $0.subjectUID,
                                 score: $0.score, date: $0.date, kind: $0.kind)
        }
        dto.grades = all(Grade.self, context).map {
            BackupFile.GradeDTO(uid: $0.uid, subject: $0.subjectUID, exam: $0.examUID, title: $0.title, value: $0.value,
                                kind: $0.kindRaw, weight: $0.weight, date: $0.date)
        }
        dto.gradeSetups = all(GradeSetup.self, context).map {
            BackupFile.GradeSetupDTO(uid: $0.uid, subject: $0.subjectUID, writtenShare: $0.writtenShare, goal: $0.goal)
        }
        dto.images = all(NoteImage.self, context).compactMap { image in
            guard let data = try? Data(contentsOf: AttachmentStore.directory.appendingPathComponent(image.storedName)) else {
                return nil as BackupFile.NoteImageDTO?
            }
            return BackupFile.NoteImageDTO(uid: image.uid, note: image.noteUID, caption: image.caption,
                                           heightLines: image.heightLines, createdAt: image.createdAt, data: data)
        }
        return dto
    }

    static func restoreLearning(_ dto: BackupFile.LearningDTO, context: ModelContext) throws {
        for item in dto.progress {
            let entry = TopicProgress(topicUID: item.topic ?? UUID())
            entry.uid = item.uid
            entry.topicUID = item.topic
            entry.understandingRaw = item.understanding
            entry.completion = item.completion
            entry.importance = item.importance
            entry.estimatedMinutes = item.estimatedMinutes
            entry.lastStudied = item.lastStudied
            entry.updatedAt = item.updatedAt
            context.insert(entry)
        }
        for item in dto.events {
            let event = UnderstandingEvent(topicUID: item.topic ?? UUID(), level: item.level, source: item.source)
            event.uid = item.uid
            event.topicUID = item.topic
            event.date = item.date
            context.insert(event)
        }
        for item in dto.plans {
            let plan = ExamPlan(examUID: item.exam ?? UUID())
            plan.uid = item.uid
            plan.examUID = item.exam
            plan.topicUIDs = item.topics
            plan.dailyMinutes = item.dailyMinutes
            plan.studyWeekdays = item.weekdays
            plan.generatedAt = item.generatedAt
            plan.createdAt = item.createdAt
            context.insert(plan)
        }
        for item in dto.sessions {
            let session = StudySession(date: item.date, minutes: item.plannedMinutes, kind: SessionKind(rawValue: item.kind) ?? .free)
            session.uid = item.uid
            session.examUID = item.exam
            session.topicUID = item.topic
            session.subjectUID = item.subject
            session.statusRaw = item.status
            session.actualMinutes = item.actualMinutes
            session.completedAt = item.completedAt
            session.isPlanned = item.isPlanned
            session.note = item.note
            context.insert(session)
        }
        for item in dto.cards {
            let card = Flashcard(front: item.front, back: item.back)
            card.uid = item.uid
            card.subjectUID = item.subject
            card.topicUID = item.topic
            card.noteUID = item.note
            card.createdAt = item.createdAt
            card.ease = item.ease
            card.intervalDays = item.intervalDays
            card.repetitions = item.repetitions
            card.lapses = item.lapses
            card.due = item.due
            card.lastReviewed = item.lastReviewed
            context.insert(card)
        }
        for item in dto.results {
            let result = PracticeResult(score: item.score, kind: item.kind)
            result.uid = item.uid
            result.topicUID = item.topic
            result.examUID = item.exam
            result.subjectUID = item.subject
            result.date = item.date
            context.insert(result)
        }
        for item in dto.grades {
            let grade = Grade(subjectUID: item.subject, value: item.value, kind: GradeKind(rawValue: item.kind) ?? .other)
            grade.uid = item.uid
            grade.examUID = item.exam
            grade.title = item.title
            grade.weight = item.weight
            grade.date = item.date
            context.insert(grade)
        }
        for item in dto.gradeSetups {
            let setup = GradeSetup(subjectUID: item.subject ?? UUID())
            setup.uid = item.uid
            setup.subjectUID = item.subject
            setup.writtenShare = item.writtenShare
            setup.goal = item.goal
            context.insert(setup)
        }
        for item in dto.images {
            let stored = try AttachmentStore.store(item.data, fileName: "bild.jpg")
            let image = NoteImage(noteUID: item.note ?? UUID(), storedName: stored.storedName)
            image.uid = item.uid
            image.noteUID = item.note
            image.caption = item.caption
            image.heightLines = item.heightLines
            image.createdAt = item.createdAt
            context.insert(image)
        }
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
