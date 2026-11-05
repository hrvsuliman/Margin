import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a long note or lesson transcript into a short summary, a to-do list and
/// flashcards, written in Margin's note markup so it can be appended to the note.
@MainActor
enum NoteSummarizer {
    enum Engine: String, CaseIterable, Identifiable {
        case claude, onDevice
        var id: String { rawValue }
        var title: String { self == .claude ? "Claude" : "Apple (offline)" }
        var privacy: String {
            self == .claude
                ? "Der Text der Notiz wird an Anthropic (Claude) gesendet und mit deinem API-Schlüssel abgerechnet."
                : "Läuft komplett auf dem iPhone. Nichts verlässt das Gerät."
        }
    }

    enum Failure: LocalizedError {
        case noEngine, empty
        var errorDescription: String? {
            switch self {
            case .noEngine: "Weder ein Claude-Schlüssel noch Apple Intelligence ist eingerichtet (Tutor › Einstellungen)."
            case .empty: "Die Notiz ist leer."
            }
        }
    }

    static var availableEngines: [Engine] {
        var engines: [Engine] = []
        if ClaudeClient.stored(model: AssistantPrefs.model) != nil { engines.append(.claude) }
        if OnDeviceModel.isAvailable { engines.append(.onDevice) }
        return engines
    }

    static let instructions = """
    Du hilfst einer Schülerin oder einem Schüler, eine Mitschrift oder Notiz nachzubereiten. Antworte auf Deutsch \
    und nur mit diesem Format, ohne Einleitung:
    ## Zusammenfassung
    3 bis 6 kurze Sätze in einfacher Sprache.
    ## Wichtig
    - die wichtigsten Punkte als Liste
    ## Aufgaben
    - [ ] Hausaufgaben oder To-dos, die im Text genannt werden, mit Termin wenn genannt (sonst den Abschnitt weglassen)
    ## Karteikarten
    Begriff :: kurze Erklärung
    (4 bis 10 Karten zu Fachbegriffen und Fakten aus dem Text)
    Erfinde nichts, was nicht im Text steht. Kein Fett, kein Kursiv.
    """

    static func summarize(_ text: String, title: String, subject: String?, engine: Engine) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw Failure.empty }
        let prompt = "Fach: \(subject ?? "unbekannt")\nTitel: \(title)\n\nText:\n\(source.prefix(60_000))"
        switch engine {
        case .claude:
            guard let client = ClaudeClient.stored(model: AssistantPrefs.model) else { throw Failure.noEngine }
            let response = try await client.send(system: instructions, messages: [["role": "user", "content": prompt]],
                                                 tools: [], effort: "low")
            let blocks = response["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .onDevice:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), OnDeviceModel.isAvailable {
                // The on-device model has a small context window: send the beginning of long transcripts.
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: String(prompt.prefix(9_000)))
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            #endif
            throw Failure.noEngine
        }
    }

    /// The open to-dos ("- [ ] …") of the "## Aufgaben" section.
    nonisolated static func todos(in summary: String) -> [String] {
        var inTasks = false
        var result: [String] = []
        for raw in summary.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                inTasks = line.dropFirst(3).lowercased().hasPrefix("aufgabe")
                continue
            }
            if inTasks, line.hasPrefix("- [ ] ") {
                let text = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { result.append(text) }
            }
        }
        return result
    }
}
