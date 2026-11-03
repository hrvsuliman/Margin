import SwiftData
import SwiftUI

/// The Tutor tab: start a conversation, continue one from the history, or hand
/// a question to the Claude app (which uses the normal Claude subscription and
/// reaches Margin through the connector).
struct TutorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]
    @State private var connector = ConnectorSync.shared
    @State private var startNew = false
    @State private var newChatID = UUID()

    private let handoffPrompts = [
        ("Was steht bei mir diese Woche an?", "calendar"),
        ("Frag mich zu meiner nächsten Prüfung ab", "questionmark.bubble"),
        ("Hilf mir, meinen Lernplan für die nächste Prüfung zu verbessern", "map"),
        ("Erklär mir mein schwächstes Thema einfach", "lightbulb"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newChatID = UUID()
                        startNew = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(Palette.marginRed)
                                .frame(width: 40, height: 40)
                                .background(Palette.marginRed.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Neues Gespräch")
                                    .font(.system(.headline, design: .serif))
                                    .foregroundStyle(Palette.ink)
                                Text(engineSummary)
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .marginRow()

                Section {
                    ForEach(handoffPrompts, id: \.0) { prompt, symbol in
                        Button {
                            ClaudeHandoff.open(prompt, context: context, openURL: openURL)
                        } label: {
                            Label(prompt, systemImage: symbol)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    NavigationLink {
                        ConnectorSettingsView()
                    } label: {
                        HStack {
                            Label("Claude-Connector", systemImage: "point.3.connected.trianglepath.dotted")
                            Spacer()
                            Text(connector.isConfigured ? (connector.lastSync.map { "abgeglichen \(Fmt.time($0))" } ?? "eingerichtet") : "einrichten")
                                .font(.caption)
                                .foregroundStyle(connector.isConfigured ? Palette.secondaryInk : Palette.marginRed)
                        }
                    }
                } header: {
                    SectionTitle("In der Claude-App (dein Abo)")
                } footer: {
                    Text("Öffnet die Claude-App mit deiner Frage – ohne API-Schlüssel, über dein normales Claude-Konto. Mit eingerichtetem Connector kann Claude dort deine Margin-Daten lesen und Karteikarten, Notizen oder Aufgaben anlegen.")
                }
                .marginRow()

                Section {
                    if threads.isEmpty {
                        Text("Deine Gespräche erscheinen hier.")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    ForEach(threads) { thread in
                        NavigationLink(value: thread) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(thread.title.isEmpty ? "Gespräch" : thread.title)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                Text("\(thread.engine == .onDevice ? "Apple" : "Claude") · \(Fmt.shortDay(thread.updatedAt)), \(Fmt.time(thread.updatedAt))")
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(threads[index]) }
                        try? context.save()
                    }
                } header: {
                    SectionTitle("Verlauf", trailing: threads.isEmpty ? nil : "\(threads.count)")
                }
                .marginRow()
            }
            .marginList()
            .navigationTitle("Tutor")
            .navigationDestination(for: ChatThread.self) { thread in
                AssistantView(thread: thread, embedded: true)
            }
            .navigationDestination(isPresented: $startNew) {
                AssistantView(embedded: true).id(newChatID)
            }
        }
    }

    private var engineSummary: String {
        var engines: [String] = []
        if AssistantPrefs.consented && Keychain.read(ClaudeClient.keyAccount) != nil { engines.append("Claude") }
        if OnDeviceModel.isAvailable { engines.append("Apple Intelligence (offline)") }
        return engines.isEmpty ? "Richte Claude oder Apple Intelligence ein" : "Mit " + engines.joined(separator: " oder ")
    }
}

/// Opens the Claude app (or claude.ai) with a prepared question.
@MainActor
enum ClaudeHandoff {
    static func open(_ question: String, context: ModelContext, openURL: OpenURLAction) {
        var prompt = question
        if ConnectorSync.shared.isConfigured {
            prompt += "\n\n(Nutze den Margin-Connector, um meine Schuldaten aus Margin zu lesen.)"
        } else {
            // Without the connector, give Claude a compact snapshot right in the message.
            let overview = MarginTools.call("get_overview", input: [:], context: context).text
            let exams = MarginTools.call("list_exams", input: [:], context: context).text
            prompt += "\n\nMein aktueller Stand aus meiner Schul-App Margin (JSON):\n\(overview.prefix(1200))\n\nPrüfungen:\n\(exams.prefix(1800))"
        }
        var components = URLComponents(string: "https://claude.ai/new")!
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        if let url = components.url { openURL(url) }
    }
}

/// Setting up the connector: deploy the relay once, paste its address, add it to Claude.
struct ConnectorSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var connector = ConnectorSync.shared
    @State private var copied: String?

    var body: some View {
        Form {
            Section {
                Text("Damit Claude ohne API-Schlüssel – mit deinem normalen Claude-Abo – auf Margin zugreifen kann, braucht es eine kleine Brücke im Internet. Die läuft kostenlos in deinem eigenen Cloudflare-Konto; Margin schickt ihr regelmäßig einen Stand deiner Daten.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .marginRow()

            Section {
                Text("Auf dem PC im Margin-Ordner: siehe README › „Claude-Connector einrichten“ (einmalig, ca. 5 Minuten: Cloudflare-Konto, dann npx wrangler deploy).")
                    .font(.footnote)
                TextField("https://margin-connector.….workers.dev", text: $connector.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("1. Brücke einrichten")
            } footer: {
                if !connector.baseURL.isEmpty && !connector.isConfigured {
                    Text("Die Adresse muss mit https:// beginnen.").foregroundStyle(Palette.marginRed)
                }
            }
            .marginRow()

            if let url = connector.connectorURL {
                Section {
                    copyBlock(url)
                    Text("claude.ai › Einstellungen › Connectors › „Eigenen Connector hinzufügen“ › diese Adresse einfügen. Danach ist Margin in der Claude-App, am PC und im Browser verfügbar.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                } header: {
                    Text("2. In Claude hinzufügen")
                } footer: {
                    Text("Die Adresse enthält deinen geheimen Schlüssel – teile sie mit niemandem.")
                }
                .marginRow()

                Section {
                    Toggle("Claude darf Änderungen vormerken", isOn: $connector.allowWrites)
                    Button {
                        Task { await connector.sync(context: context) }
                    } label: {
                        HStack {
                            Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if connector.syncing { ProgressView() }
                        }
                    }
                    if let last = connector.lastSync {
                        LabeledContent("Zuletzt", value: "\(Fmt.shortDay(last)), \(Fmt.time(last))")
                    }
                    if let error = connector.lastError {
                        Text(error).font(.footnote).foregroundStyle(Palette.marginRed)
                    }
                    ForEach(connector.applied.prefix(8), id: \.self) { entry in
                        Text(entry).font(.caption).foregroundStyle(Palette.secondaryInk)
                    }
                } header: {
                    Text("3. Abgleich")
                } footer: {
                    Text("Margin gleicht automatisch ab, wenn du die App öffnest oder etwas änderst. Was Claude anlegt, wird beim nächsten Abgleich übernommen.")
                }
                .marginRow()

                if let viewer = connector.viewerURL {
                    Section {
                        copyBlock(viewer)
                    } header: {
                        Text("Margin am PC ansehen")
                    } footer: {
                        Text("Im Browser öffnen: Aufgaben, Prüfungen, Stundenplan und Notizen (nur lesen).")
                    }
                    .marginRow()
                }

                Section {
                    Button("Neuen geheimen Schlüssel erzeugen", role: .destructive) {
                        connector.resetSecret()
                    }
                } footer: {
                    Text("Danach musst du den Connector in Claude neu hinzufügen.")
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Claude-Connector")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copyBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = text
                copied = text
                Haptics.success()
            } label: {
                Label(copied == text ? "Kopiert" : "Kopieren", systemImage: copied == text ? "checkmark" : "doc.on.doc")
                    .font(.caption)
            }
        }
    }
}
