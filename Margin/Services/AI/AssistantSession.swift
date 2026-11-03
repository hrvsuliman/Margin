import Foundation
import Observation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

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
    /// The content block sent to Claude.
    let block: [String: Any]
    /// Plain text of the material, for the on-device model (which reads text only).
    var text: String? = nil
}

/// Apple's on-device language model (Foundation Models, iOS 26).
enum OnDeviceModel {
    /// Nil when the model can be used, otherwise why not.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "Dieses iPhone unterstützt Apple Intelligence nicht (ab iPhone 15 Pro)."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Schalte Apple Intelligence in den iOS-Einstellungen ein."
            case .unavailable(.modelNotReady):
                return "Das Apple-Modell wird noch geladen. Versuch es später noch einmal."
            case .unavailable:
                return "Apple Intelligence ist gerade nicht verfügbar."
            @unknown default:
                return "Apple Intelligence ist gerade nicht verfügbar."
            }
        }
        return "Braucht iOS 26 und ein iPhone mit Apple Intelligence (ab iPhone 15 Pro)."
        #else
        return "Diese Version wurde ohne Apple Intelligence gebaut."
        #endif
    }

    static var isAvailable: Bool { unavailableReason == nil }
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
    private(set) var engine: TutorEngine

    private var messages: [[String: Any]] = []
    private let context: ModelContext
    /// The saved conversation this session writes to.
    private(set) var thread: ChatThread?
    /// A `LanguageModelSession` (kept untyped so the class works before iOS 26).
    private var onDeviceSession: AnyObject?

    init(context: ModelContext, thread: ChatThread? = nil, engine: TutorEngine? = nil) {
        self.context = context
        self.thread = thread
        self.engine = thread?.engine ?? engine ?? Self.defaultEngine
        if let thread {
            items = Self.decodeItems(thread.itemsData)
            messages = (try? JSONSerialization.jsonObject(with: thread.messagesData)) as? [[String: Any]] ?? []
        }
    }

    /// Claude when a key is stored, otherwise the on-device model if available.
    static var defaultEngine: TutorEngine {
        if Keychain.read(ClaudeClient.keyAccount) != nil && AssistantPrefs.consented { return .claudeAPI }
        return OnDeviceModel.isAvailable ? .onDevice : .claudeAPI
    }

    func switchEngine(_ engine: TutorEngine) {
        guard items.isEmpty else { return }
        self.engine = engine
    }

    static let systemPrompt = """
    Du bist der Lernassistent in Margin, einer Schul-App für eine Schülerin oder einen Schüler in Deutschland. Du hilfst beim Verstehen, Üben und Planen. Antworte auf Deutsch, klar, freundlich und ohne Floskeln.

    Grundsätze:
    - Stütze dich auf das Material, das dir gegeben wird (angehängte Texte, PDFs, Fotos, Notizen) und auf die Daten aus Margin, die du mit Werkzeugen abrufst. Erfinde keine Fakten.
    - Wenn etwas im Material nicht vorkommt, sag das ausdrücklich. Ergänzt du allgemeines Wissen, kennzeichne es als solches. Behaupte nie, etwas sei im Unterricht behandelt worden, wenn es nicht im Material steht.
    - Erkläre schrittweise und prüfe das Verständnis mit kurzen Rückfragen, statt nur fertige Lösungen zu liefern.
    - Beim Abfragen oder Quiz: eine Frage nach der anderen, auf die Antwort warten, dann bewerten und kurz erklären. Speichere am Ende das Ergebnis mit log_practice_result und passe bei klarer Evidenz das Verständnis mit set_understanding an.
    - Notizen für Margin (create_note) erscheinen in der Handschrift der Nutzerin oder des Nutzers. Nutze dafür: "# " Überschrift, "## " Unterüberschrift, "- " Aufzählung, "- [ ] " Checkliste, "> " Merkkasten, kleine Tabellen "| a | b |", "---" Trennlinie, "[[Titel]]" Link zu einer anderen Notiz, kurze Absätze. Zeilen der Form "Begriff :: Erklärung" werden automatisch zu Karteikarten. Kein Fett oder Kursiv.
    - Ändere Daten nur, wenn es zur Bitte passt, und fasse danach kurz zusammen, was du angelegt oder geändert hast.
    - Im Chat schlicht formatieren: kurze Absätze, einfache Aufzählungen.
    """

    func reset() {
        answerApproval(false)
        items = []
        messages = []
        attachments = []
        thread = nil
        onDeviceSession = nil
    }

    // MARK: History

    private struct StoredItem: Codable {
        var kind: String
        var text: String
        var extra: [String]
        var ok: Bool
    }

    private static func decodeItems(_ data: Data) -> [Item] {
        let stored = (try? JSONDecoder().decode([StoredItem].self, from: data)) ?? []
        return stored.map { entry in
            switch entry.kind {
            case "user": .user(id: UUID(), text: entry.text, attachments: entry.extra)
            case "assistant": .assistant(id: UUID(), text: entry.text)
            case "action": .action(id: UUID(), label: entry.text, ok: entry.ok)
            default: .notice(id: UUID(), text: entry.text)
            }
        }
    }

    /// Saves the conversation so it appears in the Verlauf.
    private func persist() {
        let stored: [StoredItem] = items.map { item in
            switch item {
            case let .user(_, text, attachments): StoredItem(kind: "user", text: text, extra: attachments, ok: true)
            case let .assistant(_, text): StoredItem(kind: "assistant", text: text, extra: [], ok: true)
            case let .action(_, label, ok): StoredItem(kind: "action", text: label, extra: [], ok: ok)
            case let .notice(_, text): StoredItem(kind: "notice", text: text, extra: [], ok: false)
            }
        }
        guard !stored.isEmpty else { return }
        let target: ChatThread
        if let thread {
            target = thread
        } else {
            target = ChatThread(engine: engine)
            context.insert(target)
            thread = target
        }
        if target.title.isEmpty, let first = stored.first(where: { $0.kind == "user" }) {
            let base = first.text.isEmpty ? (first.extra.first ?? "Material") : first.text
            target.title = String(base.prefix(70))
        }
        target.itemsData = (try? JSONEncoder().encode(stored)) ?? Data()
        if JSONSerialization.isValidJSONObject(messages) {
            target.messagesData = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data()
        }
        target.updatedAt = .now
        try? context.save()
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !trimmed.isEmpty || !attachments.isEmpty else { return }
        if engine == .onDevice {
            await sendOnDevice(trimmed)
            persist()
            return
        }
        defer { persist() }
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

    // MARK: On-device

    private func sendOnDevice(_ text: String) async {
        let material = attachments.compactMap { attachment in
            attachment.text.map { "Material „\(attachment.title)“:\n\($0)" }
        }.joined(separator: "\n\n")
        let skipped = attachments.filter { $0.text == nil }.map(\.title)
        items.append(.user(id: UUID(), text: text, attachments: attachments.map(\.title)))
        attachments = []
        if !skipped.isEmpty {
            items.append(.notice(id: UUID(), text: "Das Modell auf dem iPhone kann nur Text lesen – ohne: \(skipped.joined(separator: ", "))."))
        }
        // The on-device model has a small context window: keep material short.
        let prompt = [String(material.prefix(6000)), text.isEmpty ? "Schau dir das Material an." : text]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")

        busy = true
        defer { busy = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceModel.isAvailable {
            do {
                let session: LanguageModelSession
                if let existing = onDeviceSession as? LanguageModelSession {
                    session = existing
                } else {
                    session = LanguageModelSession(instructions: onDeviceInstructions())
                    onDeviceSession = session
                }
                let response = try await session.respond(to: prompt)
                items.append(.assistant(id: UUID(), text: response.content))
            } catch {
                onDeviceSession = nil
                items.append(.notice(id: UUID(), text: "Das Modell auf dem iPhone konnte nicht antworten (\(error.localizedDescription)). Bei viel Text: neues Gespräch starten oder weniger Material anhängen."))
            }
            return
        }
        #endif
        items.append(.notice(id: UUID(), text: OnDeviceModel.unavailableReason ?? "Apple Intelligence ist nicht verfügbar."))
    }

    private func onDeviceInstructions() -> String {
        var instructions = Self.systemPrompt
            .replacingOccurrences(of: "Du bist der Lernassistent in Margin", with: "Du bist der Lerntutor in Margin")
        instructions += "\n\nDu kannst in Margin nichts ändern. Wenn etwas angelegt werden soll, sag der Person, wie sie es selbst macht."
        let overview = MarginTools.call("get_overview", input: [:], context: context).text
        instructions += "\n\nAktueller Stand aus Margin (JSON): \(overview.prefix(1500))"
        return instructions
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
