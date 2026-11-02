import Foundation
import SwiftData

/// Version 1 of the database layout.
///
/// When a later phase changes a model, add `MarginSchemaV2` with the new
/// models and a `MigrationStage` below, so existing data on the iPhone is
/// migrated instead of lost.
enum MarginSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchoolSubject.self, Topic.self, Lesson.self, SchoolTask.self, Subtask.self,
            Exam.self, CalendarEvent.self, Attachment.self, Holiday.self,
        ]
    }
}

enum MarginMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MarginSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor
enum Persistence {
    static let schema = Schema(versionedSchema: MarginSchemaV1.self)

    /// The app's database, stored on the device only.
    static let container: ModelContainer = {
        do {
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(
                for: schema,
                migrationPlan: MarginMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            fatalError("Die Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }()

    /// An empty database in memory, for tests.
    static func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: MarginMigrationPlan.self, configurations: configuration)
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
