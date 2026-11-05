import CoreSpotlight
import EventKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// One-way sync into the iPhone's Calendar app: tests, homework and planned study
/// blocks land in a separate "Margin" calendar. Margin never reads or changes other calendars.
@MainActor
@Observable
final class CalendarSync {
    static let shared = CalendarSync()

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var pending: Task<Void, Never>?

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "calendar.enabled") } }
    var includeTasks: Bool { didSet { defaults.set(includeTasks, forKey: "calendar.tasks") } }
    var includeSessions: Bool { didSet { defaults.set(includeSessions, forKey: "calendar.sessions") } }
    private(set) var lastError: String?
    private(set) var lastSync: Date?

    private init() {
        isEnabled = defaults.bool(forKey: "calendar.enabled")
        includeTasks = defaults.object(forKey: "calendar.tasks") as? Bool ?? true
        includeSessions = defaults.object(forKey: "calendar.sessions") as? Bool ?? true
    }

    /// An event Margin wants in the calendar, keyed by the Margin item it comes from.
    struct Planned: Equatable {
        let key: String
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        let notes: String
    }

    static func planned(exams: [Exam], tasks: [SchoolTask], sessions: [StudySession], subjects: [SchoolSubject],
                        includeTasks: Bool, includeSessions: Bool, now: Date = .now) -> [Planned] {
        let calendar = Calendar.school
        let from = calendar.addingDays(-30, to: calendar.startOfDay(for: now))
        var result: [Planned] = []
        for exam in exams where exam.date >= from {
            let name = exam.subject?.name ?? ""
            let title = exam.displayTitle.localizedCaseInsensitiveContains(name) || name.isEmpty
                ? exam.displayTitle : "\(name): \(exam.displayTitle)"
            let day = calendar.startOfDay(for: exam.date)
            result.append(Planned(key: "exam-\(exam.uid)", title: title, start: day, end: calendar.addingDays(1, to: day),
                                  allDay: true, notes: "Aus Margin"))
        }
        if includeTasks {
            for task in tasks where !task.isDone {
                guard let due = task.dueDate, due >= from else { continue }
                let prefix = task.subject.map { "\($0.name): " } ?? ""
                let start = task.hasDueTime ? due : calendar.startOfDay(for: due)
                let end = task.hasDueTime ? due.addingTimeInterval(30 * 60) : calendar.addingDays(1, to: start)
                result.append(Planned(key: "task-\(task.uid)", title: "\(prefix)\(task.title)", start: start, end: end,
                                      allDay: !task.hasDueTime, notes: task.details.isEmpty ? "Aufgabe aus Margin" : task.details))
            }
        }
        if includeSessions {
            for session in sessions where session.status == .planned && session.date >= now {
                let subject = session.subjectUID.flatMap { id in subjects.first { $0.uid == id }?.name }
                result.append(Planned(key: "session-\(session.uid)", title: "Lernen\(subject.map { ": \($0)" } ?? "")",
                                      start: session.date, end: session.date.addingTimeInterval(Double(max(session.plannedMinutes, 10)) * 60),
                                      allDay: false, notes: session.note.isEmpty ? "Lerneinheit aus Margin" : session.note))
            }
        }
        return result
    }

    // MARK: Turning it on and off

    /// Asks for calendar access (once), creates the "Margin" calendar and syncs.
    func enable(context: ModelContext) async {
        lastError = nil
        do {
            guard try await store.requestFullAccessToEvents() else {
                lastError = "Kein Zugriff auf den Kalender. Erlauben unter Einstellungen › Datenschutz › Kalender › Margin."
                isEnabled = false
                return
            }
        } catch {
            lastError = error.localizedDescription
            isEnabled = false
            return
        }
        isEnabled = true
        await sync(context: context)
    }

    /// Turns sync off and removes the Margin calendar with its events.
    func disable() {
        isEnabled = false
        pending?.cancel()
        if let calendar = marginCalendar(create: false) {
            try? store.removeCalendar(calendar, commit: true)
        }
        defaults.removeObject(forKey: "calendar.identifier")
    }

    func scheduleSync(context: ModelContext) {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await sync(context: context)
        }
    }

    func sync(context: ModelContext) async {
        guard isEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        guard let calendar = marginCalendar(create: true) else {
            lastError = "Der Kalender „Margin“ konnte nicht angelegt werden."
            return
        }
        let wanted = Self.planned(
            exams: (try? context.fetch(FetchDescriptor<Exam>())) ?? [],
            tasks: (try? context.fetch(FetchDescriptor<SchoolTask>())) ?? [],
            sessions: (try? context.fetch(FetchDescriptor<StudySession>())) ?? [],
            subjects: (try? context.fetch(FetchDescriptor<SchoolSubject>())) ?? [],
            includeTasks: includeTasks, includeSessions: includeSessions
        )
        let range = Calendar.school.addingDays(-60, to: .now)...Calendar.school.addingDays(400, to: .now)
        let existing = store.events(matching: store.predicateForEvents(withStart: range.lowerBound, end: range.upperBound,
                                                                         calendars: [calendar]))
        var byKey: [String: EKEvent] = [:]
        for event in existing {
            // Only events Margin made carry a margin:// link; anything the user added stays untouched.
            guard let url = event.url, url.scheme == "margin" else { continue }
            if byKey[url.lastPathComponent] == nil {
                byKey[url.lastPathComponent] = event
            } else {
                try? store.remove(event, span: .thisEvent, commit: false)
            }
        }
        for item in wanted {
            let event = byKey.removeValue(forKey: item.key) ?? EKEvent(eventStore: store)
            if event.calendar == nil { event.calendar = calendar }
            if event.title != item.title { event.title = item.title }
            if event.startDate != item.start { event.startDate = item.start }
            if event.endDate != item.end { event.endDate = item.end }
            if event.isAllDay != item.allDay { event.isAllDay = item.allDay }
            if event.notes != item.notes { event.notes = item.notes }
            event.url = URL(string: "margin://calendar/\(item.key)")
            if event.hasChanges || event.isNew { try? store.save(event, span: .thisEvent, commit: false) }
        }
        for leftover in byKey.values {
            try? store.remove(leftover, span: .thisEvent, commit: false)
        }
        do {
            try store.commit()
            lastSync = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func marginCalendar(create: Bool) -> EKCalendar? {
        if let id = defaults.string(forKey: "calendar.identifier"), let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        guard create else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Margin"
        calendar.cgColor = UIColor(Palette.marginRed).cgColor
        var sources: [EKSource] = []
        if let source = store.defaultCalendarForNewEvents?.source { sources.append(source) }
        sources += store.sources.filter { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
        sources += store.sources.filter { $0.sourceType == .local }
        for source in sources {
            calendar.source = source
            if (try? store.saveCalendar(calendar, commit: true)) != nil {
                defaults.set(calendar.calendarIdentifier, forKey: "calendar.identifier")
                return calendar
            }
        }
        return nil
    }
}

/// Notes, tasks, subjects and tests in the iPhone search (swipe down on the home screen).
/// The index stays on the iPhone.
@MainActor
enum SpotlightIndex {
    private static var pending: Task<Void, Never>?

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "spotlight.enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "spotlight.enabled")
            if !newValue { CSSearchableIndex.default().deleteAllSearchableItems { _ in } }
        }
    }

    static func scheduleRefresh(context: ModelContext) {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await refresh(context: context)
        }
    }

    static func items(context: ModelContext) -> [CSSearchableItem] {
        let subjects = (try? context.fetch(FetchDescriptor<SchoolSubject>())) ?? []
        let name: (UUID?) -> String? = { id in id.flatMap { id in subjects.first { $0.uid == id }?.name } }
        var items: [CSSearchableItem] = []

        func add(_ id: String, domain: String, title: String, text: String, keywords: [String]) {
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = title
            attributes.contentDescription = String(text.prefix(300))
            attributes.keywords = keywords.filter { !$0.isEmpty }
            items.append(CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: attributes))
        }

        for note in (try? context.fetch(FetchDescriptor<NoteDocument>())) ?? [] {
            add("note:\(note.uid)", domain: "notes", title: note.title.isEmpty ? "Notiz" : note.title,
                text: LineStyle.strip(note.body.replacingOccurrences(of: "\n", with: " ")),
                keywords: ["Notiz", name(note.subjectUID) ?? "", note.folder])
        }
        for task in (try? context.fetch(FetchDescriptor<SchoolTask>())) ?? [] where !task.isDone {
            add("task:\(task.uid)", domain: "tasks", title: task.title,
                text: [task.subject?.name, task.dueDate.map { "fällig \(Fmt.date($0))" }, task.details].compactMap { $0 }.joined(separator: " · "),
                keywords: ["Aufgabe", "Hausaufgabe", task.subject?.name ?? ""])
        }
        for exam in (try? context.fetch(FetchDescriptor<Exam>())) ?? [] where exam.date >= Calendar.school.startOfDay(for: .now) {
            add("exam:\(exam.uid)", domain: "exams", title: "\(exam.subject?.name ?? "") \(exam.displayTitle)",
                text: Fmt.longDay(exam.date), keywords: ["Prüfung", "Arbeit", "Klausur"])
        }
        for subject in subjects {
            add("subject:\(subject.uid)", domain: "subjects", title: subject.name,
                text: [subject.teacher, subject.room.isEmpty ? "" : "Raum \(subject.room)"].filter { !$0.isEmpty }.joined(separator: " · "),
                keywords: ["Fach", "Pinnwand"])
        }
        return items
    }

    static func refresh(context: ModelContext) async {
        guard isEnabled else { return }
        let items = items(context: context)
        let index = CSSearchableIndex.default()
        try? await index.deleteAllSearchableItems()
        try? await index.indexSearchableItems(items)
    }
}

/// Where a search result, widget or calendar link should lead: "note:<uid>", "task:<uid>" …
enum AppRoute: Equatable {
    case note(UUID), task(UUID), exam(UUID), subject(UUID), today

    init?(identifier: String) {
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.first == "today" { self = .today; return }
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "note": self = .note(id)
        case "task": self = .task(id)
        case "exam": self = .exam(id)
        case "subject": self = .subject(id)
        default: return nil
        }
    }

    /// margin://note/<uid>, margin://today …
    init?(url: URL) {
        guard url.scheme == "margin" else { return nil }
        let host = url.host() ?? ""
        let id = url.pathComponents.dropFirst().first ?? ""
        self.init(identifier: id.isEmpty ? host : "\(host):\(id)")
    }
}
