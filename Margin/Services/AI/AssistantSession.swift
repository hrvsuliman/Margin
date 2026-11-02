import Foundation
import Observation
import SwiftData

/// Settings for the in-app assistant (the API key itself lives in the Keychain).
enum AssistantPrefs {
    @MainActor static var model: ClaudeModel {
        get { ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "assistant.model") ?? "") ?? .opus }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "assistant.model") }
    }
    /// The user agreed to send material to Anthropic.
    @MainActor static var consented: Bool {
        get { UserDefaults.standard.bool(forKey: "assistant.consent") }
        set { UserDefaults.standard.set(newValue, forKey: "assistant.consent") }
    }
    /// Ask before every change Claude wants to make.
    @MainActor static var confirmChanges: Bool {
        get { UserDefaults.standard.object(forKey: "assistant.confirm") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "assistant.confirm") }
    }
    /// Let Claude read and use Margin's data through tools.
    @MainActor static var useTools: Bool {
        get { UserDefaults.standard.object(forKey: "assistant.tools") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "assistant.tools") }
    }
}

/// Material attached to the next message.
struct AssistantAttachment: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let block: [String: Any]
}

/// One conversation with Claude, including the tool loop.
/// The raw API messages are kept exactly as returned (append-only), the
/// visible items are a readable summary of them.
@MainActor
@Observable
final class AssistantSession {
    enum Item: Identifiable {
        case user(id: UUID, text: String, attachments: [String])
        case assistant(id: UUID, text: String)
        case action(id: UUID, label: String, ok: Bool)
        case notice(id: UUID, text: String)

        var id: UUID {
            switch self {
            case .user(let id, _, _), .assistant(let id, _), .action(let id, _, _), .notice(let id, _): id
            }
        }
    }

    struct Approval: Identifiable {
        let id = UUID()
        let label: String
        let details: String
        fileprivate let resume: (Bool) -> Void
    }

    private(set) var items: [Item] = []
    private(set) var busy = false
    private(set) var approval: Approval?
    var attachments: [AssistantAttachment] = []

    private var messages: [[String: Any]] = []
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    static let systemPrompt = """
    Du bist der Lernassistent in Margin, einer Schul-App für eine Schülerin oder einen Schüler in Deutschland. Du hilfst beim Verstehen, Üben und Planen. Antworte auf Deutsch, klar, freundlich und ohne Floskeln.

    Grundsätze:
    - Stütze dich auf das Material, das dir gegeben wird (angehängte Texte, PDFs, Fotos, Notizen) und auf die Daten aus Margin, die du mit Werkzeugen abrufst. Erfinde keine Fakten.
    - Wenn etwas im Material nicht vorkommt, sag das ausdrücklich. Ergänzt du allgemeines Wissen, kennzeichne es als solches. Behaupte nie, etwas sei im Unterricht behandelt worden, wenn es nicht im Material steht.
    - Erkläre schrittweise und prüfe das Verständnis mit kurzen Rückfragen, statt nur fertige Lösungen zu liefern.
    - Beim Abfragen oder Quiz: eine Frage nach der anderen, auf die Antwort warten, dann bewerten und kurz erklären. Speichere am Ende das Ergebnis mit log_practice_result und passe bei klarer Evidenz das Verständnis mit set_understanding an.
    - Notizen für Margin (create_note) erscheinen in der Handschrift der Nutzerin oder des Nutzers. Nutze dafür: "# " Überschrift, "## " Unterüberschrift, "- " Aufzählung, kurze Absätze. Zeilen der Form "Begriff :: Erklärung" werden automatisch zu Karteikarten. Keine Tabellen, kein Fett oder Kursiv.
    - Ändere Daten nur, wenn es zur Bitte passt, und fasse danach kurz zusammen, was du angelegt oder geändert hast.
    - Im Chat schlicht formatieren: kurze Absätze, einfache Aufzählungen.
    """

    func reset() {
        answerApproval(false)
        items = []
        messages = []
        attachments = []
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard let client = ClaudeClient.stored(model: AssistantPrefs.model) else {
            items.append(.notice(id: UUID(), text: ClaudeError.noKey.localizedDescription))
            return
        }

        var content: [[String: Any]] = attachments.map(\.block)
        var prompt = trimmed.isEmpty ? "Schau dir das Material an." : trimmed
        if messages.isEmpty {
            prompt = "(Heute ist \(Fmt.longDay(.now)) \(Calendar.school.component(.year, from: .now)).)\n\n" + prompt
        }
        content.append(ClaudeClient.text(prompt))
        items.append(.user(id: UUID(), text: trimmed, attachments: attachments.map(\.title)))
        attachments = []
        let checkpoint = messages.count
        messages.append(["role": "user", "content": content])

        busy = true
        defer { busy = false }
        let tools = AssistantPrefs.useTools ? MarginTools.specs.map(\.apiDefinition) : []

        do {
            for _ in 0..<12 {
                let response = try await client.send(system: Self.systemPrompt, messages: messages, tools: tools)
                let blocks = response["content"] as? [[String: Any]] ?? []
                // Send back exactly what came in (thinking and fallback blocks included).
                messages.append(["role": "assistant", "content": blocks])

                let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
                    .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { items.append(.assistant(id: UUID(), text: text)) }

                switch response["stop_reason"] as? String {
                case "tool_use":
                    let results = await runTools(blocks)
                    messages.append(["role": "user", "content": results])
                    continue
                case "refusal":
                    items.append(.notice(id: UUID(), text: "Claude hat diese Anfrage abgelehnt. Formuliere sie anders oder frag nach etwas anderem."))
                case "max_tokens":
                    items.append(.notice(id: UUID(), text: "Die Antwort wurde abgeschnitten. Schreib „weiter“, damit Claude fortfährt."))
                default:
                    break
                }
                return
            }
            items.append(.notice(id: UUID(), text: "Claude hat zu viele Schritte gebraucht und wurde angehalten."))
        } catch {
            items.append(.notice(id: UUID(), text: error.localizedDescription))
            // Roll back this exchange so the history stays valid for the next try.
            if messages.count > checkpoint { messages.removeSubrange(checkpoint...) }
        }
    }

    /// Runs every tool call of one response; all results go back in one message.
    private func runTools(_ blocks: [[String: Any]]) async -> [[String: Any]] {
        var results: [[String: Any]] = []
        for block in blocks where block["type"] as? String == "tool_use" {
            guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
            let input = block["input"] as? [String: Any] ?? [:]
            let spec = MarginTools.spec(named: name)
            let label = spec?.label ?? name

            if let spec, !spec.readOnly, AssistantPrefs.confirmChanges {
                let allowed = await ask(label: label, details: Self.describe(input))
                guard allowed else {
                    items.append(.action(id: UUID(), label: label, ok: false))
                    results.append(["type": "tool_result", "tool_use_id": id, "is_error": true,
                                    "content": "Die Nutzerin oder der Nutzer hat diese Änderung abgelehnt. Frag nach, was stattdessen passieren soll."])
                    continue
                }
            }
            let outcome = MarginTools.call(name, input: input, context: context)
            if !(spec?.readOnly ?? true) || outcome.isError {
                items.append(.action(id: UUID(), label: label, ok: !outcome.isError))
            }
            results.append(["type": "tool_result", "tool_use_id": id, "content": outcome.text, "is_error": outcome.isError])
        }
        return results
    }

    private func ask(label: String, details: String) async -> Bool {
        await withCheckedContinuation { continuation in
            approval = Approval(label: label, details: details) { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func answerApproval(_ allowed: Bool) {
        guard let current = approval else { return }
        approval = nil
        current.resume(allowed)
    }

    /// Readable summary of a tool input for the approval card.
    static func describe(_ input: [String: Any]) -> String {
        input.sorted { $0.key < $1.key }.map { key, value in
            let text: String
            switch value {
            case let array as [Any]: text = array.map { "\($0)" }.joined(separator: ", ")
            default: text = "\(value)"
            }
            return "\(key): \(text.prefix(400))"
        }.joined(separator: "\n")
    }
}
