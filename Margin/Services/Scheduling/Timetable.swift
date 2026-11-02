import Foundation

enum Timetable {
    /// The first day after `date` that is one of `weekdays` (1 = Monday) and not a holiday.
    static func nextDay(
        withWeekdays weekdays: Set<Int>,
        after date: Date,
        calendar: Calendar = .school,
        isHoliday: (Date) -> Bool = { _ in false }
    ) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        var day = calendar.startOfDay(for: date)
        for _ in 0..<120 {
            day = calendar.addingDays(1, to: day)
            if weekdays.contains(calendar.isoWeekday(of: day)) && !isHoliday(day) {
                return day
            }
        }
        return nil
    }

    /// The next day the subject is taught, e.g. for "homework due next lesson".
    static func nextLessonDay(for subject: SchoolSubject, after date: Date = .now, holidays: [Holiday]) -> Date? {
        let weekdays = Set((subject.lessons ?? []).map(\.weekday))
        return nextDay(withWeekdays: weekdays, after: date) { day in
            holidays.contains { $0.contains(day) }
        }
    }

    struct UpcomingLesson {
        let lesson: Lesson
        let start: Date
        let end: Date
        var isNow: Bool
    }

    /// The lesson happening now, or else the next one within two weeks.
    static func currentOrNextLesson(lessons: [Lesson], holidays: [Holiday], now: Date = .now) -> UpcomingLesson? {
        let calendar = Calendar.school
        let today = calendar.startOfDay(for: now)
        for offset in 0..<14 {
            let day = calendar.addingDays(offset, to: today)
            if holidays.contains(where: { $0.contains(day) }) { continue }
            let weekday = calendar.isoWeekday(of: day)
            let candidates = lessons
                .filter { $0.weekday == weekday }
                .map { lesson in
                    (lesson, calendar.date(on: day, minute: lesson.startMinute), calendar.date(on: day, minute: lesson.endMinute))
                }
                .filter { $0.2 > now }
                .sorted { $0.1 < $1.1 }
            if let first = candidates.first {
                return UpcomingLesson(lesson: first.0, start: first.1, end: first.2, isNow: first.1 <= now)
            }
        }
        return nil
    }
}
