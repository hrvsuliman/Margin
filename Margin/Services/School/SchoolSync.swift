import Foundation
import Observation
import SwiftData
import UserNotifications

/// One lesson as delivered by WebUntis or a calendar feed.
struct ImportedLesson: Equatable, Sendable {
    var id: String
    var start: Date
    var end: Date
    var subject: String
    var room: String
    var teacher: String
    var status: EntryStatus
    var info: String
}

enum SchoolSyncError: LocalizedError {
    case login(String)
    case server(String)
    case invalidAddress

    var errorDescription: String? {
        switch self {
        case .login(let message): "Anmeldung bei WebUntis fehlgeschlagen: \(message)"
        case .server(let message): "WebUntis: \(message)"
        case .invalidAddress: "Die Adresse ist ungültig."
        }
    }
}

/// WebUntis through its JSON-RPC interface (the one Untis' own older apps used).
/// It isn't an official public API: whether students may read their timetable
/// depends on the school's settings.
struct UntisClient {
    let server: String
    let school: String
    let user: String
    let password: String

    private let session = URLSession(configuration: .ephemeral)

    private var endpoint: URL? {
        var host = server.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        host = host.components(separatedBy: "/").first ?? host
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/WebUntis/jsonrpc.do"
        components.queryItems = [URLQueryItem(name: "school", value: school.trimmingCharacters(in: .whitespaces))]
        return components.url
    }

    private func call(_ method: String, _ params: [String: Any]) async throws -> Any {
        guard let endpoint else { throw SchoolSyncError.invalidAddress }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "method": method, "params": params, "jsonrpc": "2.0",
        ])
        let (data, _) = try await session.data(for: request)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SchoolSyncError.server("Unerwartete Antwort. Stimmen Server und Schulname?")
        }
        if let error = json["error"] as? [String: Any] {
            throw SchoolSyncError.server(error["message"] as? String ?? "Fehler")
        }
        return json["result"] ?? [:]
    }

    func fetch(from: Date, to: Date) async throws -> [ImportedLesson] {
        let auth: Any
        do {
            auth = try await call("authenticate", ["user": user, "password": password, "client": "Margin"])
        } catch let SchoolSyncError.server(message) {
            throw SchoolSyncError.login(message)
        }
        guard let login = auth as? [String: Any], let personID = login["personId"] as? Int else {
            throw SchoolSyncError.login("Kein Zugriff auf den eigenen Stundenplan.")
        }
        let personType = login["personType"] as? Int ?? 5
        defer { Task { _ = try? await call("logout", [:]) } }

        let result = try await call("getTimetable", ["options": [
            "element": ["id": personID, "type": personType],
            "startDate": Self.untisDate(from), "endDate": Self.untisDate(to),
            "showInfo": true, "showSubstText": true, "showLsText": true,
            "subjectFields": ["name", "longname"], "roomFields": ["name"], "teacherFields": ["name"],
        ]])
        let periods = result as? [[String: Any]] ?? []
        return periods.compactMap(Self.lesson)
    }

    static func untisDate(_ date: Date) -> Int {
        let parts = Calendar.school.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Turns one WebUntis period into a lesson.
    static func lesson(_ period: [String: Any]) -> ImportedLesson? {
        guard let date = period["date"] as? Int, let startTime = period["startTime"] as? Int,
              let endTime = period["endTime"] as? Int else { return nil }
        let calendar = Calendar.school
        guard let day = calendar.date(from: DateComponents(year: date / 10000, month: date / 100 % 100, day: date % 100)) else { return nil }
        let start = calendar.date(on: day, minute: startTime / 100 * 60 + startTime % 100)
        let end = calendar.date(on: day, minute: endTime / 100 * 60 + endTime % 100)
        func names(_ key: String, _ field: String = "name") -> [String] {
            (period[key] as? [[String: Any]] ?? []).compactMap { $0[field] as? String ?? $0["name"] as? String }
        }
        let subject = names("su", "longname").first ?? names("su").first ?? (period["lstext"] as? String ?? "")
        var status: EntryStatus = .normal
        switch period["code"] as? String {
        case "cancelled": status = .cancelled
        case "irregular": status = .changed
        default: break
        }
        if (period["activityType"] as? String)?.lowercased().contains("prüfung") == true { status = .exam }
        let info = [period["substText"] as? String, period["info"] as? String, period["lstext"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != subject }
            .joined(separator: " · ")
        let id = (period["id"] as? Int).map { String($0) } ?? "\(date)-\(startTime)-\(subject)"
        return ImportedLesson(id: id, start: start, end: end, subject: subject, room: names("ro").joined(separator: ", "),
                              teacher: names("te").joined(separator: ", "), status: status, info: info)
    }
}

/// A calendar feed (iCal / webcal), e.g. the iCal link WebUntis offers,
/// or any school calendar.
enum ICalFeed {
    static func fetch(_ address: String) async throws -> [ImportedLesson] {
        var text = address.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
        guard let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { throw SchoolSyncError.invalidAddress }
        let (data, _) = try await URLSession(configuration: .ephemeral).data(from: url)
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ ics: String) -> [ImportedLesson] {
        // Unfold continuation lines (RFC 5545: a line starting with a space continues the previous one).
        let unfolded = ics.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var lessons: [ImportedLesson] = []
        var current: [String: (params: String, value: String)]?
        for line in unfolded.components(separatedBy: "\n") {
            if line == "BEGIN:VEVENT" { current = [:]; continue }
            if line == "END:VEVENT" {
                if let fields = current, let lesson = lesson(from: fields) { lessons.append(lesson) }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let name = head.components(separatedBy: ";").first ?? head
            current?[name] = (head, value)
        }
        return lessons
    }

    private static func lesson(from fields: [String: (params: String, value: String)]) -> ImportedLesson? {
        guard let startField = fields["DTSTART"], let start = date(startField.value, params: startField.params) else { return nil }
        let end = fields["DTEND"].flatMap { date($0.value, params: $0.params) } ?? start.addingTimeInterval(45 * 60)
        func text(_ key: String) -> String {
            (fields[key]?.value ?? "")
                .replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\,", with: ",")
                .replacingOccurrences(of: "\\;", with: ";").trimmingCharacters(in: .whitespaces)
        }
        let cancelled = text("STATUS").uppercased() == "CANCELLED" || text("SUMMARY").lowercased().contains("entfall")
        return ImportedLesson(id: fields["UID"]?.value ?? "\(start.timeIntervalSince1970)-\(text("SUMMARY"))",
                              start: start, end: end, subject: text("SUMMARY"), room: text("LOCATION"), teacher: "",
                              status: cancelled ? .cancelled : .normal, info: text("DESCRIPTION"))
    }

    /// 20261102T080000Z (UTC), 20261102T080000 (local or TZID) or 20261102 (whole day).
    static func date(_ value: String, params: String) -> Date? {
        let digits = value.filter { $0.isNumber }
        guard digits.count >= 8 else { return nil }
        let year = Int(digits.prefix(4)) ?? 0
        let month = Int(digits.dropFirst(4).prefix(2)) ?? 1
        let day = Int(digits.dropFirst(6).prefix(2)) ?? 1
        var components = DateComponents(year: year, month: month, day: day)
        if digits.count >= 12 {
            components.hour = Int(digits.dropFirst(8).prefix(2))
            components.minute = Int(digits.dropFirst(10).prefix(2))
        }
        var calendar = Calendar(identifier: .gregorian)
        if value.hasSuffix("Z") {
            calendar.timeZone = TimeZone(identifier: "UTC")!
        } else if let tzRange = params.range(of: "TZID="),
                  let zone = TimeZone(identifier: String(params[tzRange.upperBound...]).components(separatedBy: ";").first ?? "") {
            calendar.timeZone = zone
        } else {
            calendar.timeZone = .current
        }
        return calendar.date(from: components)
    }
}

/// Settings and the import into the database, plus notifications for changes.
@MainActor
@Observable
final class SchoolSync {
    static let shared = SchoolSync()
    static let passwordAccount = "untis-password"

    enum Source: String, CaseIterable, Identifiable {
        case off, untis, ical
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Aus"
            case .untis: "WebUntis"
            case .ical: "Kalender-Link (iCal)"
            }
        }
    }

    var source: Source = Source(rawValue: UserDefaults.standard.string(forKey: "school.source") ?? "") ?? .off {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "school.source") }
    }
    var server: String = UserDefaults.standard.string(forKey: "school.server") ?? "" {
        didSet { UserDefaults.standard.set(server, forKey: "school.server") }
    }
    var school: String = UserDefaults.standard.string(forKey: "school.name") ?? "" {
        didSet { UserDefaults.standard.set(school, forKey: "school.name") }
    }
    var user: String = UserDefaults.standard.string(forKey: "school.user") ?? "" {
        didSet { UserDefaults.standard.set(user, forKey: "school.user") }
    }
    var icalURL: String = UserDefaults.standard.string(forKey: "school.ical") ?? "" {
        didSet { UserDefaults.standard.set(icalURL, forKey: "school.ical") }
    }
    var createMissingSubjects: Bool = UserDefaults.standard.object(forKey: "school.createSubjects") as? Bool ?? true {
        didSet { UserDefaults.standard.set(createMissingSubjects, forKey: "school.createSubjects") }
    }
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "school.lastSync") as? Date
    private(set) var lastError: String?
    private(set) var syncing = false

    var isConfigured: Bool {
        switch source {
        case .off: false
        case .untis: !server.isEmpty && !school.isEmpty && !user.isEmpty && Keychain.read(Self.passwordAccount) != nil
        case .ical: !icalURL.isEmpty
        }
    }

    /// Refreshes if the last import is older than `maxAge`.
    func refreshIfNeeded(context: ModelContext, maxAge: TimeInterval = 30 * 60) async {
        guard isConfigured, (lastSync.map { Date.now.timeIntervalSince($0) > maxAge } ?? true) else { return }
        await refresh(context: context)
    }

    func refresh(context: ModelContext) async {
        guard isConfigured, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let calendar = Calendar.school
        let from = calendar.startOfWeek(for: .now)
        let to = calendar.addingDays(20, to: from)
        do {
            let lessons: [ImportedLesson]
            switch source {
            case .untis:
                lessons = try await UntisClient(server: server, school: school, user: user,
                                                password: Keychain.read(Self.passwordAccount) ?? "").fetch(from: from, to: to)
            case .ical:
                lessons = try await ICalFeed.fetch(icalURL)
            case .off:
                return
            }
            let changes = apply(lessons, source: source.rawValue, context: context)
            notify(changes)
            lastSync = .now
            lastError = nil
            UserDefaults.standard.set(lastSync, forKey: "school.lastSync")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stores the lessons; returns the ones that newly became cancelled or changed in the next two days.
    @discardableResult
    func apply(_ lessons: [ImportedLesson], source: String, context: ModelContext) -> [ImportedLesson] {
        let existing = ((try? context.fetch(FetchDescriptor<TimetableEntry>())) ?? []).filter { $0.source == source }
        let previous = Dictionary(existing.map { ($0.externalID, $0.status) }, uniquingKeysWith: { a, _ in a })
        for entry in existing { context.delete(entry) }

        var subjects = (try? context.fetch(FetchDescriptor<SchoolSubject>())) ?? []
        let soon = Calendar.school.addingDays(2, to: Calendar.school.startOfDay(for: .now))
        var changes: [ImportedLesson] = []

        for lesson in lessons {
            let entry = TimetableEntry(externalID: lesson.id, source: source, start: lesson.start, end: lesson.end)
            entry.subjectName = lesson.subject
            entry.room = lesson.room
            entry.teacher = lesson.teacher
            entry.status = lesson.status
            entry.info = lesson.info
            if let subject = Self.match(lesson.subject, in: subjects) {
                entry.subjectUID = subject.uid
            } else if createMissingSubjects, source == "untis", !lesson.subject.isEmpty {
                let colors = SubjectColor.allCases
                let created = SchoolSubject(name: lesson.subject, colorKey: colors[subjects.count % colors.count].rawValue,
                                            sortIndex: subjects.count)
                context.insert(created)
                subjects.append(created)
                entry.subjectUID = created.uid
            }
            context.insert(entry)
            if lesson.status != .normal, lesson.start > .now, lesson.start < soon, previous[lesson.id] != lesson.status {
                changes.append(lesson)
            }
        }
        try? context.save()
        return changes
    }

    static func match(_ name: String, in subjects: [SchoolSubject]) -> SchoolSubject? {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return subjects.first { $0.name.compare(key, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? subjects.first { key.count >= 3 && ($0.name.localizedCaseInsensitiveContains(key) || key.localizedCaseInsensitiveContains($0.name)) }
    }

    private func notify(_ changes: [ImportedLesson]) {
        for lesson in changes.prefix(5) {
            let content = UNMutableNotificationContent()
            let when = "\(Fmt.relativeDay(lesson.start).capitalized), \(Fmt.time(lesson.start))"
            content.title = lesson.status == .cancelled ? "\(lesson.subject) fällt aus" : "\(lesson.subject): \(lesson.status.title)"
            content.body = [when, lesson.room.isEmpty ? nil : "Raum \(lesson.room)", lesson.info.isEmpty ? nil : lesson.info]
                .compactMap { $0 }.joined(separator: " · ")
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "untis-\(lesson.id)", content: content, trigger: nil))
        }
    }
}
