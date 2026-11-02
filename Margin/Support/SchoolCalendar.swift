import Foundation

extension Locale {
    /// The app's UI is German, so dates are always formatted the German way.
    static let margin = Locale(identifier: "de_DE")
}

extension Calendar {
    /// Gregorian calendar with German conventions: weeks start on Monday,
    /// week numbers follow ISO 8601 (as used in German schools).
    static let school: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .margin
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }()

    /// 1 = Monday … 7 = Sunday.
    func isoWeekday(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7 + 1
    }

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    func addingDays(_ days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// The given day at a minute of the day (e.g. 480 = 08:00). Safe across daylight-saving changes.
    func date(on day: Date, minute: Int) -> Date {
        let clamped = max(0, min(minute, 24 * 60 - 1))
        return self.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day) ?? day
    }

    func minuteOfDay(_ date: Date) -> Int {
        let parts = dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Whole days from `from` to `to`, ignoring the time of day.
    func daysBetween(_ from: Date, _ to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to)).day ?? 0
    }

    /// 42 days (6 weeks) covering the month of `date`, starting on a Monday.
    func monthGrid(for date: Date) -> [Date] {
        let firstOfMonth = dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
        let start = startOfWeek(for: firstOfMonth)
        return (0..<42).map { addingDays($0, to: start) }
    }
}

/// German date and time texts used across the app.
enum Fmt {
    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .margin
        formatter.calendar = .school
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let longDayFormatter = formatter("EEEEdMMMM")
    private static let shortDayFormatter = formatter("EEEdMMM")
    private static let dateFormatter = formatter("ddMMyyyy")
    private static let monthFormatter = formatter("MMMMyyyy")
    private static let weekdayFormatter = formatter("EEEE")
    private static let shortWeekdayFormatter = formatter("EEE")
    private static let dayMonthFormatter = formatter("dMMM")

    /// "Montag, 2. November"
    static func longDay(_ date: Date) -> String { longDayFormatter.string(from: date) }
    /// "Mo., 2. Nov."
    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }
    /// "02.11.2026"
    static func date(_ date: Date) -> String { dateFormatter.string(from: date) }
    /// "November 2026"
    static func month(_ date: Date) -> String { monthFormatter.string(from: date) }
    /// "Montag"
    static func weekday(_ date: Date) -> String { weekdayFormatter.string(from: date) }
    /// "Mo."
    static func shortWeekday(_ date: Date) -> String { shortWeekdayFormatter.string(from: date) }
    /// "2. Nov."
    static func dayMonth(_ date: Date) -> String { dayMonthFormatter.string(from: date) }

    /// "08:05"
    static func time(_ date: Date) -> String {
        clock(Calendar.school.minuteOfDay(date))
    }

    /// Minute of day as "08:05".
    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// "45 Min.", "1 Std.", "1 Std. 30 Min."
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) Min."
        case (_, 0): return "\(hours) Std."
        default: return "\(hours) Std. \(rest) Min."
        }
    }

    /// Short German weekday names, Monday first: index 1…7.
    static func weekdayName(_ isoWeekday: Int, short: Bool = false) -> String {
        let long = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
        let abbreviations = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let index = max(1, min(7, isoWeekday)) - 1
        return short ? abbreviations[index] : long[index]
    }

    /// "heute", "morgen", "in 5 Tagen", "gestern", "vor 3 Tagen", "übermorgen"
    static func relativeDay(_ date: Date, from now: Date = .now) -> String {
        let days = Calendar.school.daysBetween(now, date)
        switch days {
        case 0: return "heute"
        case 1: return "morgen"
        case 2: return "übermorgen"
        case -1: return "gestern"
        case let d where d < 0: return "vor \(-d) Tagen"
        default: return "in \(days) Tagen"
        }
    }
}
