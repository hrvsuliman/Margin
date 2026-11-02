import Foundation
import SwiftData

// Database versions. Every released layout stays listed here so existing data
// on the iPhone is migrated, never lost. A model class may only appear unchanged
// in an older version; once an existing model changes, freeze a copy of the old
// one inside that version's enum.

/// Phase 1: school planner.
enum MarginSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchoolSubject.self, Topic.self, Lesson.self, SchoolTask.self, Subtask.self,
            Exam.self, CalendarEvent.self, Attachment.self, Holiday.self,
        ]
    }
}

/// Phase 2: adds handwriting profiles and handwritten notes.
enum MarginSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        MarginSchemaV1.models + [HandwritingProfile.self, GlyphSample.self, NoteDocument.self]
    }
}

/// Phase 3: learning (topics' understanding, plans, sessions, flashcards),
/// grades and images in notes.
enum MarginSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        MarginSchemaV2.models + [
            TopicProgress.self, UnderstandingEvent.self, ExamPlan.self, StudySession.self,
            Flashcard.self, PracticeResult.self, Grade.self, GradeSetup.self, NoteImage.self,
        ]
    }
}

enum MarginMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MarginSchemaV1.self, MarginSchemaV2.self, MarginSchemaV3.self] }

    static var stages: [MigrationStage] {
        // Each version only added new tables, so SwiftData can migrate automatically.
        [
            .lightweight(fromVersion: MarginSchemaV1.self, toVersion: MarginSchemaV2.self),
            .lightweight(fromVersion: MarginSchemaV2.self, toVersion: MarginSchemaV3.self),
        ]
    }
}

@MainActor
enum Persistence {
    static let schema = Schema(versionedSchema: MarginSchemaV3.self)

    /// The app's database, stored on the device only.
    static let container: ModelContainer = {
        do {
            return try makeContainer(configuration: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            fatalError("Die Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }()

    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: MarginMigrationPlan.self, configurations: configuration)
    }

    /// An empty database in memory, for tests.
    static func inMemoryContainer() throws -> ModelContainer {
        try makeContainer(configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}

extension ModelContext {
    /// Saves and refreshes the reminder notifications.
    @MainActor
    func commit() {
        do {
            try save()
        } catch {
            assertionFailure("Speichern fehlgeschlagen: \(error)")
        }
        ReminderService.scheduleRefresh(context: self)
    }
}
