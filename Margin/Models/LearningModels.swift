import Foundation
import SwiftData

// Phase 3 models. They refer to existing records (topics, exams, subjects,
// notes) by `uid` instead of relationships, so the Phase 1/2 models stay
// unchanged and the database migrates automatically.

/// The five understanding levels, separate from how much material is done.
enum Understanding: Int, CaseIterable, Identifiable, Codable, Sendable {
    case notYet = 0, barely, basics, mostly, confident

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .notYet: "Verstehe ich noch nicht"
        case .barely: "Verstehe ich kaum"
        case .basics: "Grundlagen sitzen"
        case .mostly: "Verstehe ich größtenteils"
        case .confident: "Kann ich erklären und anwenden"
        }
    }

    var short: String {
        switch self {
        case .notYet: "Neu"
        case .barely: "Kaum"
        case .basics: "Basics"
        case .mostly: "Größtenteils"
        case .confident: "Sicher"
        }
    }

    /// 0 … 1
    var fraction: Double { Double(rawValue) / 4 }
}

/// How well a topic is understood and how far the material is done.
@Model
final class TopicProgress {
    var uid: UUID = UUID()
    var topicUID: UUID?
    var understandingRaw: Int = 0
    /// How much of the material (notes, exercises) is done, 0 … 1.
    var completion: Double = 0
    /// 0 = low, 1 = normal, 2 = high.
    var importance: Int = 1
    var estimatedMinutes: Int = 60
    var lastStudied: Date?
    var updatedAt: Date = Date.now

    init(topicUID: UUID) {
        self.uid = UUID()
        self.topicUID = topicUID
        self.updatedAt = .now
    }

    var understanding: Understanding {
        get { Understanding(rawValue: understandingRaw) ?? .notYet }
        set { understandingRaw = newValue.rawValue }
    }
}

/// A change of understanding, for the "progress over time" statistics.
@Model
final class UnderstandingEvent {
    var uid: UUID = UUID()
    var topicUID: UUID?
    var level: Int = 0
    var date: Date = Date.now
    /// "manual", "session", "cards", "quiz", "assistant"
    var source: String = "manual"

    init(topicUID: UUID, level: Int, source: String) {
        self.uid = UUID()
        self.topicUID = topicUID
        self.level = level
        self.source = source
        self.date = .now
    }
}

/// Which topics an exam covers and how the learning plan should be built.
@Model
final class ExamPlan {
    var uid: UUID = UUID()
    var examUID: UUID?
    var topicUIDs: [UUID] = []
    /// Maximum learning minutes per day for this plan.
    var dailyMinutes: Int = 45
    /// ISO weekdays (1 = Monday) on which learning sessions may be planned.
    var studyWeekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    var generatedAt: Date?
    var createdAt: Date = Date.now

    init(examUID: UUID) {
        self.uid = UUID()
        self.examUID = examUID
        self.createdAt = .now
    }
}

enum SessionKind: String, CaseIterable, Codable, Sendable {
    case learn, practice, review, mockTest, finalReview, free

    var title: String {
        switch self {
        case .learn: "Verstehen"
        case .practice: "Üben"
        case .review: "Wiederholen"
        case .mockTest: "Probeklausur"
        case .finalReview: "Letzte Wiederholung"
        case .free: "Lernen"
        }
    }

    var symbol: String {
        switch self {
        case .learn: "lightbulb"
        case .practice: "pencil.and.outline"
        case .review: "arrow.triangle.2.circlepath"
        case .mockTest: "list.clipboard"
        case .finalReview: "flag.checkered"
        case .free: "timer"
        }
    }
}

enum SessionStatus: String, Codable, Sendable {
    case planned, done, skipped
}

/// A planned or completed learning session (also what the focus timer logs).
@Model
final class StudySession {
    var uid: UUID = UUID()
    var examUID: UUID?
    var topicUID: UUID?
    var subjectUID: UUID?
    var kindRaw: String = SessionKind.free.rawValue
    var statusRaw: String = SessionStatus.planned.rawValue
    /// Start of the session (planned day; time of day is a suggestion).
    var date: Date = Date.now
    var plannedMinutes: Int = 30
    var actualMinutes: Int = 0
    var completedAt: Date?
    /// False for sessions started freely with the focus timer.
    var isPlanned: Bool = true
    var note: String = ""

    init(date: Date, minutes: Int, kind: SessionKind) {
        self.uid = UUID()
        self.date = date
        self.plannedMinutes = minutes
        self.kindRaw = kind.rawValue
    }

    var kind: SessionKind {
        get { SessionKind(rawValue: kindRaw) ?? .free }
        set { kindRaw = newValue.rawValue }
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
}

/// A flashcard with spaced-repetition state (SM-2).
@Model
final class Flashcard {
    var uid: UUID = UUID()
    var subjectUID: UUID?
    var topicUID: UUID?
    /// Set when the card was taken from a "Begriff :: Erklärung" line of a note.
    var noteUID: UUID?
    var front: String = ""
    var back: String = ""
    var createdAt: Date = Date.now
    var ease: Double = 2.5
    var intervalDays: Int = 0
    var repetitions: Int = 0
    var lapses: Int = 0
    var due: Date = Date.now
    var lastReviewed: Date?

    init(front: String, back: String) {
        self.uid = UUID()
        self.front = front
        self.back = back
        self.createdAt = .now
        self.due = .now
    }
}

/// The result of practising a topic (flashcards, quiz, mock test).
@Model
final class PracticeResult {
    var uid: UUID = UUID()
    var topicUID: UUID?
    var examUID: UUID?
    var subjectUID: UUID?
    /// 0 … 1
    var score: Double = 0
    var date: Date = Date.now
    /// "cards", "quiz", "mock"
    var kind: String = "cards"

    init(score: Double, kind: String) {
        self.uid = UUID()
        self.score = score
        self.kind = kind
        self.date = .now
    }
}

enum GradeKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case written, oral, test, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .written: "Schriftlich"
        case .oral: "Mündlich"
        case .test: "Test"
        case .other: "Sonstige"
        }
    }

    /// Written exams count towards the written part, everything else towards the oral part.
    var isWritten: Bool { self == .written }
}

/// One grade. `value` is 1.0 … 6.0, or 0 … 15 points in the Oberstufe.
@Model
final class Grade {
    var uid: UUID = UUID()
    var subjectUID: UUID?
    var examUID: UUID?
    var title: String = ""
    var value: Double = 2
    var kindRaw: String = GradeKind.written.rawValue
    /// Weight within its group (written or oral), e.g. 2 for a double test.
    var weight: Double = 1
    var date: Date = Date.now

    init(subjectUID: UUID?, value: Double, kind: GradeKind) {
        self.uid = UUID()
        self.subjectUID = subjectUID
        self.value = value
        self.kindRaw = kind.rawValue
        self.date = .now
    }

    var kind: GradeKind {
        get { GradeKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

/// How a subject's grades are weighted (written share), and the grade goal.
@Model
final class GradeSetup {
    var uid: UUID = UUID()
    var subjectUID: UUID?
    /// Share of the written part, 0 … 1 (e.g. 0.5 = 50 % written, 50 % oral).
    var writtenShare: Double = 0.5
    /// Target average, nil if none.
    var goal: Double?

    init(subjectUID: UUID) {
        self.uid = UUID()
        self.subjectUID = subjectUID
    }
}

/// An image placed in a handwritten note (photo, board picture, diagram).
/// The note body refers to it with a line `[[Bild:<uid>]]`.
@Model
final class NoteImage {
    var uid: UUID = UUID()
    var noteUID: UUID?
    /// File name in the attachment store.
    var storedName: String = ""
    var caption: String = ""
    /// Height on the page in lines.
    var heightLines: Int = 7
    var createdAt: Date = Date.now

    init(noteUID: UUID, storedName: String) {
        self.uid = UUID()
        self.noteUID = noteUID
        self.storedName = storedName
        self.createdAt = .now
    }
}

/// Which AI answers in a tutor conversation.
enum TutorEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Claude through the Anthropic API with the user's own key.
    case claudeAPI
    /// Apple's on-device model (iOS 26, Apple Intelligence devices) – free and offline.
    case onDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeAPI: "Claude (API-Schlüssel)"
        case .onDevice: "Apple Intelligence (auf dem iPhone)"
        }
    }
}

/// A saved tutor conversation ("Verlauf").
@Model
final class ChatThread {
    var uid: UUID = UUID()
    var title: String = ""
    var engineRaw: String = TutorEngine.claudeAPI.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// The visible chat (JSON).
    var itemsData: Data = Data()
    /// The raw API messages, so a Claude conversation can be continued exactly (JSON).
    var messagesData: Data = Data()

    init(engine: TutorEngine) {
        self.uid = UUID()
        self.engineRaw = engine.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var engine: TutorEngine {
        get { TutorEngine(rawValue: engineRaw) ?? .claudeAPI }
        set { engineRaw = newValue.rawValue }
    }
}
