import Foundation
import Observation
import SwiftUI

/// One lesson period in the school's bell schedule ("Stundenraster").
struct Period: Codable, Hashable, Identifiable {
    var id = UUID()
    var startMinute: Int
    var endMinute: Int
}

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Wie System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// When open tasks without their own reminder should notify.
enum DefaultTaskReminder: String, CaseIterable, Identifiable, Codable {
    case off, eveningBefore, morningOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Keine"
        case .eveningBefore: "Am Vortag um 17:00"
        case .morningOf: "Am Fälligkeitstag um 7:00"
        }
    }
}

/// User preferences, stored in UserDefaults. School data itself lives in SwiftData.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    var schoolType: SchoolType { didSet { defaults.set(schoolType.rawValue, forKey: Keys.schoolType) } }
    /// ISO weekdays with lessons, 1 = Monday.
    var schoolDays: [Int] { didSet { defaults.set(schoolDays, forKey: Keys.schoolDays) } }
    var periods: [Period] { didSet { save(periods, forKey: Keys.periods) } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var defaultTaskReminder: DefaultTaskReminder {
        didSet { defaults.set(defaultTaskReminder.rawValue, forKey: Keys.taskReminder) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        schoolType = SchoolType(rawValue: defaults.string(forKey: Keys.schoolType) ?? "") ?? .gymnasium
        schoolDays = (defaults.array(forKey: Keys.schoolDays) as? [Int]) ?? [1, 2, 3, 4, 5]
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        defaultTaskReminder = DefaultTaskReminder(rawValue: defaults.string(forKey: Keys.taskReminder) ?? "")
            ?? .eveningBefore
        if let data = defaults.data(forKey: Keys.periods),
           let stored = try? JSONDecoder().decode([Period].self, from: data) {
            periods = stored
        } else {
            periods = Self.standardPeriods
        }
    }

    /// A common German bell schedule: 45-minute lessons, breaks after the 2nd, 4th and 6th.
    static let standardPeriods: [Period] = [
        (480, 525), (525, 570), (590, 635), (635, 680),
        (700, 745), (745, 790), (820, 865), (865, 910),
        (915, 960), (960, 1005),
    ].map { Period(startMinute: $0.0, endMinute: $0.1) }

    var sortedSchoolDays: [Int] { schoolDays.sorted() }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private enum Keys {
        static let schoolType = "settings.schoolType"
        static let schoolDays = "settings.schoolDays"
        static let periods = "settings.periods"
        static let appearance = "settings.appearance"
        static let taskReminder = "settings.defaultTaskReminder"
    }
}

/// Settings as they are written into a backup file.
struct SettingsSnapshot: Codable {
    var schoolType: SchoolType
    var schoolDays: [Int]
    var periods: [Period]
    var appearance: Appearance
    var defaultTaskReminder: DefaultTaskReminder

    @MainActor
    init(_ settings: AppSettings) {
        schoolType = settings.schoolType
        schoolDays = settings.schoolDays
        periods = settings.periods
        appearance = settings.appearance
        defaultTaskReminder = settings.defaultTaskReminder
    }

    @MainActor
    func apply(to settings: AppSettings) {
        settings.schoolType = schoolType
        settings.schoolDays = schoolDays
        settings.periods = periods
        settings.appearance = appearance
        settings.defaultTaskReminder = defaultTaskReminder
    }
}
