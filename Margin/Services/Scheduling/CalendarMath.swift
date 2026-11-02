import Foundation

/// Pure date calculations for the calendar. No SwiftUI, no database, fully unit-tested.
enum CalendarMath {
    /// Occurrences of a (possibly repeating) event that overlap `window`.
    ///
    /// - Parameters:
    ///   - start: start of the first occurrence.
    ///   - end: end of the first occurrence. For all-day events pass the start of the last day.
    ///   - until: last day on which an occurrence may start (inclusive), or nil for forever.
    static func occurrences(
        start: Date,
        end: Date,
        isAllDay: Bool,
        recurrence: Recurrence,
        until: Date?,
        in window: DateInterval,
        calendar: Calendar
    ) -> [DateInterval] {
        let firstStart = isAllDay ? calendar.startOfDay(for: start) : start
        let firstEnd: Date = {
            if isAllDay { return calendar.addingDays(1, to: calendar.startOfDay(for: max(start, end))) }
            return max(start, end)
        }()
        let duration = firstEnd.timeIntervalSince(firstStart)

        func overlaps(_ s: Date) -> Bool {
            let e = s.addingTimeInterval(duration)
            if duration == 0 { return s >= window.start && s < window.end }
            return s < window.end && e > window.start
        }

        guard let step = recurrence.step else {
            return overlaps(firstStart) ? [DateInterval(start: firstStart, duration: duration)] : []
        }

        let lastAllowedStart = until.map { calendar.addingDays(1, to: calendar.startOfDay(for: $0)) }

        // Jump close to the window instead of walking from the first occurrence.
        var index = 0
        if step.component == .day {
            let daysToWindow = calendar.dateComponents([.day], from: firstStart, to: window.start).day ?? 0
            index = max(0, (daysToWindow - Int(duration / 86_400)) / step.value - 1)
        }

        var result: [DateInterval] = []
        var guardCounter = 0
        while guardCounter < 2_000 {
            guardCounter += 1
            guard let s = calendar.date(byAdding: step.component, value: step.value * index, to: firstStart) else { break }
            index += 1
            if s >= window.end { break }
            if let lastAllowedStart, s >= lastAllowedStart { break }
            if overlaps(s) {
                result.append(DateInterval(start: s, duration: duration))
            }
        }
        return result
    }

    static func occurrences(of event: CalendarEvent, in window: DateInterval, calendar: Calendar) -> [DateInterval] {
        occurrences(
            start: event.start,
            end: event.end,
            isAllDay: event.isAllDay,
            recurrence: event.recurrence,
            until: event.recurrenceEnd,
            in: window,
            calendar: calendar
        )
    }

    /// Every day (start of day) in the window.
    static func days(in window: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: window.start)
        while day < window.end && days.count < 400 {
            days.append(day)
            day = calendar.addingDays(1, to: day)
        }
        return days
    }

    /// Whether `day` falls inside any of the holiday ranges (both ends inclusive).
    static func isHoliday(_ day: Date, ranges: [(start: Date, end: Date)], calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: day)
        return ranges.contains { calendar.startOfDay(for: $0.start) <= d && d <= calendar.startOfDay(for: $0.end) }
    }
}

/// Places overlapping blocks of a day timeline side by side.
enum TimelineLayout {
    struct Placement: Equatable {
        var column: Int
        var columnCount: Int
    }

    /// For each range (in the given order), which column it goes in and how many
    /// columns its group of overlapping ranges needs.
    static func place(_ ranges: [(start: Double, end: Double)]) -> [Placement] {
        var placements = Array(repeating: Placement(column: 0, columnCount: 1), count: ranges.count)
        let order = ranges.indices.sorted { ranges[$0].start < ranges[$1].start }

        var clusterMembers: [Int] = []
        var columnEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func closeCluster() {
            for member in clusterMembers {
                placements[member].columnCount = max(1, columnEnds.count)
            }
            clusterMembers = []
            columnEnds = []
        }

        for index in order {
            let range = ranges[index]
            let end = max(range.end, range.start + 1)
            if range.start >= clusterEnd {
                closeCluster()
                clusterEnd = -Double.infinity
            }
            if let free = columnEnds.firstIndex(where: { $0 <= range.start }) {
                columnEnds[free] = end
                placements[index].column = free
            } else {
                columnEnds.append(end)
                placements[index].column = columnEnds.count - 1
            }
            clusterMembers.append(index)
            clusterEnd = max(clusterEnd, end)
        }
        closeCluster()
        return placements
    }
}
