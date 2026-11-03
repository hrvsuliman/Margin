import AppIntents
import Foundation
import SwiftData

/// Subjects for Siri and the Shortcuts app.
struct SubjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fach"
    static let defaultQuery = SubjectQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct SubjectQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SubjectEntity] {
        allSubjects().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SubjectEntity] {
        allSubjects()
    }

    @MainActor
    private func allSubjects() -> [SubjectEntity] {
        let subjects = (try? Persistence.container.mainContext.fetch(FetchDescriptor<SchoolSubject>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        return subjects.map { SubjectEntity(id: $0.uid, name: $0.name) }
    }
}

/// "Hey Siri, Hausaufgabe in Margin eintragen"
struct AddHomeworkIntent: AppIntent {
    static let title: LocalizedStringResource = "Hausaufgabe eintragen"
    static let description = IntentDescription("Trägt eine Aufgabe in Margin ein.")

    @Parameter(title: "Aufgabe", requestValueDialog: "Was ist die Aufgabe?")
    var text: String

    @Parameter(title: "Fach")
    var subject: SubjectEntity?

    @Parameter(title: "Fällig am")
    var due: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.container.mainContext
        let task = SchoolTask(title: text, kind: .homework)
        context.insert(task)
        if let subject {
            task.subject = try? context.fetch(FetchDescriptor<SchoolSubject>()).first { $0.uid == subject.id }
        }
        if let due {
            task.dueDate = Calendar.school.startOfDay(for: due)
        } else if let subject = task.subject {
            task.dueDate = Timetable.nextLessonDay(for: subject, holidays: (try? context.fetch(FetchDescriptor<Holiday>())) ?? [])
        }
        context.commit()
        let when = task.dueDate.map { " – fällig \(Fmt.relativeDay($0))" } ?? ""
        return .result(dialog: "Eingetragen: \(text)\(when).")
    }
}

/// "Hey Siri, was ist in Margin fällig?"
struct WhatsDueIntent: AppIntent {
    static let title: LocalizedStringResource = "Was ist fällig?"
    static let description = IntentDescription("Liest offene Aufgaben bis morgen und die nächste Prüfung vor.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.container.mainContext
        let calendar = Calendar.school
        let limit = calendar.addingDays(2, to: calendar.startOfDay(for: .now))
        let tasks = ((try? context.fetch(FetchDescriptor<SchoolTask>())) ?? [])
            .filter { !$0.isDone && ($0.dueDate.map { $0 < limit } ?? false) }
        let exam = ((try? context.fetch(FetchDescriptor<Exam>())) ?? [])
            .filter { $0.date >= calendar.startOfDay(for: .now) }
            .min { $0.date < $1.date }
        var parts: [String] = []
        if tasks.isEmpty {
            parts.append("Bis morgen ist nichts fällig.")
        } else {
            parts.append("\(tasks.count) Aufgabe\(tasks.count == 1 ? "" : "n") bis morgen: " +
                         tasks.prefix(4).map { "\($0.subject?.name ?? $0.kind.title) – \($0.title)" }.joined(separator: ", ") + ".")
        }
        if let exam { parts.append("Nächste Prüfung: \(exam.displayTitle) \(Fmt.relativeDay(exam.date)).") }
        return .result(dialog: "\(parts.joined(separator: " "))")
    }
}

/// "Hey Siri, Fokuszeit in Margin starten" – opens the app on the Lernen tab.
struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Fokuszeit starten"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "intent.startFocus")
        return .result()
    }
}

struct MarginShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddHomeworkIntent(),
            phrases: [
                "Hausaufgabe in \(.applicationName) eintragen",
                "Neue Aufgabe in \(.applicationName)",
                "\(.applicationName) Hausaufgabe",
            ],
            shortTitle: "Hausaufgabe",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: WhatsDueIntent(),
            phrases: [
                "Was ist in \(.applicationName) fällig",
                "Was steht in \(.applicationName) an",
            ],
            shortTitle: "Was ist fällig?",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Fokuszeit in \(.applicationName) starten"],
            shortTitle: "Fokuszeit",
            systemImageName: "timer"
        )
    }
}
