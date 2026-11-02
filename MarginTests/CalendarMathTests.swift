import XCTest
@testable import Margin

final class CalendarMathTests: XCTestCase {
    private let calendar = Calendar.school

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func window(_ from: Date, days: Int) -> DateInterval {
        DateInterval(start: from, end: calendar.addingDays(days, to: from))
    }

    func testSingleEventInsideWindow() {
        let result = CalendarMath.occurrences(
            start: date(2026, 11, 3, 15), end: date(2026, 11, 3, 16), isAllDay: false,
            recurrence: .never, until: nil, in: window(date(2026, 11, 2), days: 7), calendar: calendar
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.start, date(2026, 11, 3, 15))
        XCTAssertEqual(result.first?.end, date(2026, 11, 3, 16))
    }

    func testSingleEventOutsideWindow() {
        let result = CalendarMath.occurrences(
            start: date(2026, 12, 3, 15), end: date(2026, 12, 3, 16), isAllDay: false,
            recurrence: .never, until: nil, in: window(date(2026, 11, 2), days: 7), calendar: calendar
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testWeeklyEventRepeatsOncePerWeek() {
        let result = CalendarMath.occurrences(
            start: date(2026, 9, 1, 14), end: date(2026, 9, 1, 15), isAllDay: false,
            recurrence: .weekly, until: nil, in: window(date(2026, 11, 2), days: 28), calendar: calendar
        )
        XCTAssertEqual(result.map(\.start), [
            date(2026, 11, 3, 14), date(2026, 11, 10, 14), date(2026, 11, 17, 14), date(2026, 11, 24, 14),
        ])
    }

    func testRecurrenceStopsAfterUntilDay() {
        let result = CalendarMath.occurrences(
            start: date(2026, 11, 2, 9), end: date(2026, 11, 2, 10), isAllDay: false,
            recurrence: .daily, until: date(2026, 11, 4), in: window(date(2026, 11, 1), days: 14), calendar: calendar
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.last?.start, date(2026, 11, 4, 9))
    }

    func testMonthlyKeepsDayOfMonth() {
        // Jan 31 → Feb 28 → Mar 31: always counted from the first occurrence.
        let result = CalendarMath.occurrences(
            start: date(2027, 1, 31, 12), end: date(2027, 1, 31, 13), isAllDay: false,
            recurrence: .monthly, until: nil, in: DateInterval(start: date(2027, 1, 1), end: date(2027, 4, 1)),
            calendar: calendar
        )
        XCTAssertEqual(result.map(\.start), [date(2027, 1, 31, 12), date(2027, 2, 28, 12), date(2027, 3, 31, 12)])
    }

    func testDailyEventStartedLongAgoYieldsOneOccurrencePerDay() {
        let result = CalendarMath.occurrences(
            start: date(2025, 1, 1, 7), end: date(2025, 1, 1, 8), isAllDay: false,
            recurrence: .daily, until: nil, in: window(date(2026, 11, 2), days: 1), calendar: calendar
        )
        XCTAssertEqual(result.map(\.start), [date(2026, 11, 2, 7)])
    }

    func testMultiDayAllDayEventCoversEveryDay() {
        // A class trip from Monday to Wednesday (end = start of the last day).
        let trip = (start: date(2026, 11, 2), end: date(2026, 11, 4))
        for (day, expected) in [(date(2026, 11, 1), 0), (date(2026, 11, 2), 1), (date(2026, 11, 4), 1), (date(2026, 11, 5), 0)] {
            let result = CalendarMath.occurrences(
                start: trip.start, end: trip.end, isAllDay: true, recurrence: .never, until: nil,
                in: window(day, days: 1), calendar: calendar
            )
            XCTAssertEqual(result.count, expected, "day \(day)")
        }
    }

    func testHolidayRangeIsInclusive() {
        let ranges = [(start: date(2026, 10, 12), end: date(2026, 10, 24))]
        XCTAssertTrue(CalendarMath.isHoliday(date(2026, 10, 12, 9), ranges: ranges, calendar: calendar))
        XCTAssertTrue(CalendarMath.isHoliday(date(2026, 10, 24, 23), ranges: ranges, calendar: calendar))
        XCTAssertFalse(CalendarMath.isHoliday(date(2026, 10, 25), ranges: ranges, calendar: calendar))
    }
}

final class TimelineLayoutTests: XCTestCase {
    func testSeparateBlocksUseOneColumn() {
        let placements = TimelineLayout.place([(0, 45), (45, 90), (100, 145)])
        XCTAssertEqual(placements, Array(repeating: .init(column: 0, columnCount: 1), count: 3))
    }

    func testOverlappingBlocksSitSideBySide() {
        let placements = TimelineLayout.place([(0, 90), (30, 60)])
        XCTAssertEqual(placements, [.init(column: 0, columnCount: 2), .init(column: 1, columnCount: 2)])
    }

    func testFreedColumnIsReusedWithinGroup() {
        // A overlaps B and C; B ends before C starts, so C reuses B's column.
        let placements = TimelineLayout.place([(0, 120), (10, 40), (50, 80)])
        XCTAssertEqual(placements.map(\.column), [0, 1, 1])
        XCTAssertEqual(placements.map(\.columnCount), [2, 2, 2])
    }
}

final class SchoolCalendarTests: XCTestCase {
    private let calendar = Calendar.school

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testWeekStartsOnMonday() {
        XCTAssertEqual(calendar.isoWeekday(of: date(2026, 11, 2)), 1)
        XCTAssertEqual(calendar.isoWeekday(of: date(2026, 11, 8)), 7)
        XCTAssertEqual(calendar.startOfWeek(for: date(2026, 11, 4)), date(2026, 11, 2))
        XCTAssertEqual(calendar.startOfWeek(for: date(2026, 11, 8)), date(2026, 11, 2))
    }

    func testMonthGridStartsOnMondayBeforeFirstOfMonth() {
        let grid = calendar.monthGrid(for: date(2026, 11, 15))
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(grid.first, date(2026, 10, 26))
    }

    func testGermanFormatting() {
        XCTAssertEqual(Fmt.clock(485), "08:05")
        XCTAssertEqual(Fmt.duration(minutes: 45), "45 Min.")
        XCTAssertEqual(Fmt.duration(minutes: 60), "1 Std.")
        XCTAssertEqual(Fmt.duration(minutes: 90), "1 Std. 30 Min.")
        XCTAssertEqual(Fmt.weekdayName(1), "Montag")
        XCTAssertEqual(Fmt.weekdayName(7, short: true), "So")
        XCTAssertEqual(Fmt.date(date(2026, 11, 2)), "02.11.2026")
        XCTAssertEqual(Fmt.longDay(date(2026, 11, 2)), "Montag, 2. November")
    }

    func testRelativeDays() {
        let now = date(2026, 11, 2)
        XCTAssertEqual(Fmt.relativeDay(date(2026, 11, 2), from: now), "heute")
        XCTAssertEqual(Fmt.relativeDay(date(2026, 11, 3), from: now), "morgen")
        XCTAssertEqual(Fmt.relativeDay(date(2026, 11, 9), from: now), "in 7 Tagen")
        XCTAssertEqual(Fmt.relativeDay(date(2026, 10, 30), from: now), "vor 3 Tagen")
    }

    func testNextLessonDaySkipsHolidays() {
        let monday = date(2026, 11, 2)
        XCTAssertEqual(Timetable.nextDay(withWeekdays: [1, 3], after: monday), date(2026, 11, 4))
        let wednesday = date(2026, 11, 4)
        let next = Timetable.nextDay(withWeekdays: [1, 3], after: monday) { calendar.isDate($0, inSameDayAs: wednesday) }
        XCTAssertEqual(next, date(2026, 11, 9))
        XCTAssertNil(Timetable.nextDay(withWeekdays: [], after: monday))
    }
}
