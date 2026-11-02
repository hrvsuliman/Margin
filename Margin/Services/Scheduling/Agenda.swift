import SwiftUI

/// What an agenda entry points back to, so tapping it can open the right screen.
enum AgendaSource {
    case lesson(Lesson)
    case exam(Exam)
    case task(SchoolTask)
    case event(CalendarEvent)
    case holiday(Holiday)
    case session(StudySession)
    case entry(TimetableEntry)
}

/// One entry in the calendar or on the Today screen.
struct AgendaItem: Identifiable {
    let id: String
    let source: AgendaSource
    let title: String
    let detail: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let symbol: String
    let isDone: Bool

    /// Lower sorts first among all-day items.
    fileprivate var allDayRank: Int {
        switch source {
        case .holiday: 0
        case .exam: 1
        case .task: 2
        case .event: 3
        case .session: 4
        case .lesson, .entry: 5
        }
    }

    var isSession: Bool {
        if case .session = source { return true }
        return false
    }

    var isLesson: Bool {
        switch source {
        case .lesson, .entry: true
        default: false
        }
    }

    /// A school change (cancellation, substitution) from WebUntis.
    var isChange: Bool {
        if case .entry(let entry) = source { return entry.status != .normal }
        return false
    }

    var isHoliday: Bool {
        if case .holiday = source { return true }
        return false
    }
}

extension EventCategory {
    var color: Color {
        switch self {
        case .personal: SubjectColor.indigo.color
        case .school: SubjectColor.blue.color
        case .project: SubjectColor.teal.color
        case .presentation: SubjectColor.violet.color
        case .trip: SubjectColor.green.color
        case .other: SubjectColor.gray.color
        }
    }
}

/// Turns the stored lessons, exams, tasks, events and holidays into
/// per-day agenda entries. Lessons are skipped on holidays.
struct Agenda {
    var lessons: [Lesson]
    var exams: [Exam]
    var tasks: [SchoolTask]
    var events: [CalendarEvent]
    var holidays: [Holiday]
    var calendar: Calendar = .school
    var sessions: [StudySession] = []
    /// Real lessons from WebUntis or a calendar feed; they replace the weekly timetable on their days.
    var entries: [TimetableEntry] = []
    /// Topic and subject lookups for naming and colouring study sessions.
    var topics: [Topic] = []
    var subjects: [SchoolSubject] = []

    func holiday(on day: Date) -> Holiday? {
        holidays.first { $0.contains(day, calendar: calendar) }
    }

    func items(on day: Date) -> [AgendaItem] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.addingDays(1, to: dayStart)
        let window = DateInterval(start: dayStart, end: dayEnd)
        let stamp = Int(dayStart.timeIntervalSince1970)
        var items: [AgendaItem] = []

        let holiday = holiday(on: dayStart)
        if let holiday {
            items.append(AgendaItem(
                id: "holiday-\(holiday.uid)-\(stamp)", source: .holiday(holiday),
                title: holiday.name.isEmpty ? "Schulfrei" : holiday.name,
                detail: "bis \(Fmt.dayMonth(holiday.end))",
                start: dayStart, end: dayEnd, isAllDay: true,
                color: Palette.secondaryInk, symbol: "sun.max", isDone: false
            ))
        } else if case let dayEntries = entries.filter({ calendar.isDate($0.start, inSameDayAs: dayStart) }), !dayEntries.isEmpty {
            for entry in dayEntries {
                let subject = entry.subjectUID.flatMap { id in subjects.first { $0.uid == id } }
                let detail = [entry.status.title, entry.room.isEmpty ? nil : "Raum \(entry.room)", entry.info.isEmpty ? nil : entry.info]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                items.append(AgendaItem(
                    id: "entry-\(entry.uid)", source: .entry(entry),
                    title: subject?.name ?? (entry.subjectName.isEmpty ? "Unterricht" : entry.subjectName),
                    detail: detail, start: entry.start, end: entry.end, isAllDay: false,
                    color: entry.status == .cancelled ? Palette.faintInk : (subject?.color.color ?? SubjectColor.gray.color),
                    symbol: entry.status == .cancelled ? "xmark.circle" : "book", isDone: entry.status == .cancelled
                ))
            }
        } else {
            let weekday = calendar.isoWeekday(of: dayStart)
            for lesson in lessons where lesson.weekday == weekday {
                let start = calendar.date(on: dayStart, minute: lesson.startMinute)
                let end = calendar.date(on: dayStart, minute: max(lesson.endMinute, lesson.startMinute))
                let room = lesson.room.isEmpty ? (lesson.subject?.room ?? "") : lesson.room
                items.append(AgendaItem(
                    id: "lesson-\(lesson.uid)-\(stamp)", source: .lesson(lesson),
                    title: lesson.subject?.name ?? "Unterricht",
                    detail: room.isEmpty ? "" : "Raum \(room)",
                    start: start, end: end, isAllDay: false,
                    color: lesson.subject?.color.color ?? SubjectColor.gray.color,
                    symbol: "book", isDone: false
                ))
            }
        }

        for exam in exams where calendar.isDate(exam.date, inSameDayAs: dayStart) {
            let end = exam.date.addingTimeInterval(Double(max(exam.durationMinutes, 0)) * 60)
            items.append(AgendaItem(
                id: "exam-\(exam.uid)", source: .exam(exam),
                title: exam.displayTitle,
                detail: exam.hasTime ? "\(Fmt.time(exam.date))–\(Fmt.time(end))" : exam.kind.title,
                start: exam.date, end: end, isAllDay: !exam.hasTime,
                color: exam.subject?.color.color ?? Palette.marginRed,
                symbol: "list.clipboard", isDone: false
            ))
        }

        for task in tasks {
            guard let due = task.dueDate, calendar.isDate(due, inSameDayAs: dayStart) else { continue }
            var detail = task.subject?.name ?? task.kind.title
            if task.hasDueTime { detail += " · bis \(Fmt.time(due))" }
            items.append(AgendaItem(
                id: "task-\(task.uid)", source: .task(task),
                title: task.title, detail: detail,
                start: due, end: due, isAllDay: true,
                color: task.subject?.color.color ?? SubjectColor.gray.color,
                symbol: task.kind.symbol, isDone: task.isDone
            ))
        }

        for event in events {
            for occurrence in CalendarMath.occurrences(of: event, in: window, calendar: calendar) {
                var detail = event.isAllDay ? event.category.title
                    : "\(Fmt.time(occurrence.start))–\(Fmt.time(occurrence.end))"
                if !event.location.isEmpty { detail += " · \(event.location)" }
                items.append(AgendaItem(
                    id: "event-\(event.uid)-\(Int(occurrence.start.timeIntervalSince1970))", source: .event(event),
                    title: event.title, detail: detail,
                    start: max(occurrence.start, dayStart), end: min(occurrence.end, dayEnd),
                    isAllDay: event.isAllDay, color: event.subject?.color.color ?? event.category.color,
                    symbol: event.category.symbol, isDone: false
                ))
            }
        }

        for session in sessions where session.status != .skipped && calendar.isDate(session.date, inSameDayAs: dayStart) {
            let topic = session.topicUID.flatMap { id in topics.first { $0.uid == id } }
            let subject = session.subjectUID.flatMap { id in subjects.first { $0.uid == id } } ?? topic?.subject
            let end = session.date.addingTimeInterval(Double(max(session.plannedMinutes, 5)) * 60)
            items.append(AgendaItem(
                id: "session-\(session.uid)", source: .session(session),
                title: [topic?.title, session.kind.title].compactMap { $0 }.joined(separator: " · "),
                detail: session.status == .done ? "erledigt · \(session.actualMinutes) Min." : "Lernen · \(session.plannedMinutes) Min.",
                start: session.date, end: end, isAllDay: false,
                color: subject?.color.color ?? Palette.marginRed,
                symbol: session.kind.symbol, isDone: session.status == .done
            ))
        }

        return items.sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if a.isAllDay { return a.allDayRank < b.allDayRank }
            return a.start < b.start
        }
    }

    /// Up to three colour dots for the month grid: exams, due tasks and events.
    /// Lessons are left out, otherwise every school day would look the same.
    func markers(on day: Date) -> [Color] {
        Array(items(on: day).filter { !$0.isLesson && !$0.isHoliday && !$0.isDone }.map(\.color).prefix(3))
    }
}
