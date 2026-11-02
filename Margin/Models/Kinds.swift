import Foundation

// Enums are stored in SwiftData as their raw values (String / Int).
// That keeps the database simple and makes queries reliable on iOS 17.

enum TaskKind: String, CaseIterable, Identifiable, Codable {
    case homework, assignment, presentation, project, examPrep, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homework: "Hausaufgabe"
        case .assignment: "Abgabe"
        case .presentation: "Präsentation"
        case .project: "Projekt"
        case .examPrep: "Prüfungsvorbereitung"
        case .general: "Allgemein"
        }
    }

    var symbol: String {
        switch self {
        case .homework: "book.closed"
        case .assignment: "tray.and.arrow.up"
        case .presentation: "person.wave.2"
        case .project: "folder"
        case .examPrep: "graduationcap"
        case .general: "checklist"
        }
    }
}

enum TaskPriority: Int, CaseIterable, Identifiable, Codable {
    case low = 0, normal = 1, high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Niedrig"
        case .normal: "Mittel"
        case .high: "Hoch"
        }
    }
}

enum TaskStatus: String, CaseIterable, Identifiable, Codable {
    case open, inProgress, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Offen"
        case .inProgress: "In Arbeit"
        case .done: "Erledigt"
        }
    }
}

enum ExamKind: String, CaseIterable, Identifiable, Codable {
    case classTest, klausur, test, oral, finalExam, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classTest: "Klassenarbeit"
        case .klausur: "Klausur"
        case .test: "Test"
        case .oral: "Mündliche Prüfung"
        case .finalExam: "Abschlussprüfung"
        case .other: "Prüfung"
        }
    }
}

enum EventCategory: String, CaseIterable, Identifiable, Codable {
    case personal, school, project, presentation, trip, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Privat"
        case .school: "Schule"
        case .project: "Projekt"
        case .presentation: "Präsentation"
        case .trip: "Ausflug"
        case .other: "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .personal: "person"
        case .school: "building.columns"
        case .project: "folder"
        case .presentation: "person.wave.2"
        case .trip: "bus"
        case .other: "calendar"
        }
    }
}

enum Recurrence: String, CaseIterable, Identifiable, Codable {
    case never, daily, weekly, biweekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: "Nie"
        case .daily: "Täglich"
        case .weekly: "Wöchentlich"
        case .biweekly: "Alle 2 Wochen"
        case .monthly: "Monatlich"
        case .yearly: "Jährlich"
        }
    }

    /// Calendar step between two occurrences.
    var step: (component: Calendar.Component, value: Int)? {
        switch self {
        case .never: nil
        case .daily: (.day, 1)
        case .weekly: (.day, 7)
        case .biweekly: (.day, 14)
        case .monthly: (.month, 1)
        case .yearly: (.year, 1)
        }
    }
}

enum SchoolType: String, CaseIterable, Identifiable, Codable {
    case gymnasium, oberstufe, realschule, gesamtschule, oberschule, berufsschule, grundschule, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gymnasium: "Gymnasium (Sek. I)"
        case .oberstufe: "Gymnasiale Oberstufe"
        case .realschule: "Realschule"
        case .gesamtschule: "Gesamtschule"
        case .oberschule: "Ober-/Sekundarschule"
        case .berufsschule: "Berufsschule"
        case .grundschule: "Grundschule"
        case .other: "Andere"
        }
    }

    /// The usual name for a written exam at this type of school.
    var defaultExamKind: ExamKind {
        switch self {
        case .oberstufe, .berufsschule: .klausur
        default: .classTest
        }
    }
}
