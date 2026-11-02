import Foundation
import Observation
import Security
import SwiftData

/// Keeps the Margin Connector (a small relay on the user's own Cloudflare
/// account) up to date, so Claude – with the normal Claude subscription, no
/// API key – can read Margin's data and queue changes as an MCP connector.
@MainActor
@Observable
final class ConnectorSync {
    static let shared = ConnectorSync()
    private static let secretAccount = "connector-secret"

    var baseURL: String = UserDefaults.standard.string(forKey: "connector.url") ?? "" {
        didSet { UserDefaults.standard.set(baseURL, forKey: "connector.url") }
    }
    var allowWrites: Bool = UserDefaults.standard.bool(forKey: "connector.allowWrites") {
        didSet { UserDefaults.standard.set(allowWrites, forKey: "connector.allowWrites") }
    }
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "connector.lastSync") as? Date
    private(set) var lastError: String?
    private(set) var syncing = false
    /// What Claude changed in the last syncs (newest first).
    private(set) var applied: [String] = UserDefaults.standard.stringArray(forKey: "connector.applied") ?? []

    private var pending: Task<Void, Never>?

    var isConfigured: Bool { normalizedBase != nil }

    var secret: String {
        if let existing = Keychain.read(Self.secretAccount) { return existing }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        Keychain.write(value, account: Self.secretAccount)
        return value
    }

    func resetSecret() {
        Keychain.delete(Self.secretAccount)
        _ = secret
    }

    private var normalizedBase: String? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard base.hasPrefix("https://"), URL(string: base) != nil else { return nil }
        return base
    }

    var connectorURL: String? { normalizedBase.map { "\($0)/mcp/\(secret)" } }
    var viewerURL: String? { normalizedBase.map { "\($0)/view/\(secret)" } }

    // MARK: Syncing

    /// Debounced sync after local changes.
    func scheduleSync(context: ModelContext) {
        guard isConfigured else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await sync(context: context)
        }
    }

    func sync(context: ModelContext) async {
        guard let base = normalizedBase, !syncing, let url = URL(string: "\(base)/sync/\(secret)") else { return }
        syncing = true
        defer { syncing = false }
        do {
            var inbox = try await post(url, body: ["snapshot": Self.snapshot(context: context, allowWrites: allowWrites)])
            if !inbox.isEmpty {
                var acked: [String] = []
                for item in inbox {
                    guard let id = item["id"] as? String, let tool = item["tool"] as? String else { continue }
                    let args = item["args"] as? [String: Any] ?? [:]
                    let label = MarginTools.spec(named: tool)?.label ?? tool
                    let outcome = MarginTools.call(tool, input: args, context: context)
                    applied.insert("\(Fmt.shortDay(.now)) \(Fmt.time(.now)) · \(label)\(outcome.isError ? " – fehlgeschlagen" : "")", at: 0)
                    acked.append(id)
                }
                applied = Array(applied.prefix(30))
                UserDefaults.standard.set(applied, forKey: "connector.applied")
                // Send the updated data and confirm the applied changes.
                inbox = try await post(url, body: ["snapshot": Self.snapshot(context: context, allowWrites: allowWrites), "acked": acked])
            }
            lastSync = .now
            lastError = nil
            UserDefaults.standard.set(lastSync, forKey: "connector.lastSync")
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func post(_ url: URL, body: [String: Any]) async throws -> [[String: Any]] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["inbox"] as? [[String: Any]] ?? []
    }

    // MARK: Snapshot

    /// Everything the read tools can answer, computed with the same tools the
    /// in-app assistant and the local MCP server use.
    static func snapshot(context: ModelContext, allowWrites: Bool) -> [String: Any] {
        func read(_ tool: String, _ input: [String: Any] = [:]) -> Any {
            let outcome = MarginTools.call(tool, input: input, context: context)
            return (try? JSONSerialization.jsonObject(with: Data(outcome.text.utf8))) ?? outcome.text
        }
        let subjects = (try? context.fetch(FetchDescriptor<SchoolSubject>())) ?? []
        var topics: [String: Any] = [:]
        for subject in subjects { topics[subject.name] = read("list_topics", ["subject": subject.uid.uuidString]) }

        let notes = (try? context.fetch(FetchDescriptor<NoteDocument>())) ?? []
        let subjectNames = Dictionary(subjects.map { ($0.uid, $0.name) }, uniquingKeysWith: { a, _ in a })
        let noteEntries: [[String: Any]] = notes.sorted { $0.updatedAt > $1.updatedAt }.map { note in
            [
                "id": note.uid.uuidString,
                "title": note.title.isEmpty ? "Ohne Titel" : note.title,
                "subject": note.subjectUID.flatMap { subjectNames[$0] } ?? "",
                "date": Fmt.date(note.noteDate),
                "updated": note.updatedAt.timeIntervalSince1970,
                "body": String(note.body.prefix(60_000)),
            ]
        }
        let parts = Calendar.school.dateComponents([.year, .month, .day], from: .now)
        let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)

        return [
            "syncedAt": "\(Fmt.longDay(.now)), \(Fmt.time(.now))",
            "today": today,
            "allowWrites": allowWrites,
            "instructions": MCPHandler.instructions,
            "tools": MarginTools.specs.map(\.mcpDefinition),
            "data": [
                "overview": read("get_overview"),
                "tasks": read("list_tasks", ["status": "all"]),
                "exams": read("list_exams", ["include_past": true]),
                "timetable": read("get_timetable"),
                "topics": topics,
                "notes": noteEntries.map { entry in entry.filter { $0.key != "body" && $0.key != "updated" } },
                "cards": read("list_flashcards"),
                "stats": read("get_study_stats"),
            ] as [String: Any],
            "notes": noteEntries,
        ]
    }
}
