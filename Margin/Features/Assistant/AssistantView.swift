import PDFKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Chat with Claude about your own material. Changes to Margin need your OK.
struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \NoteDocument.updatedAt, order: .reverse) private var notes: [NoteDocument]

    var initialAttachments: [AssistantAttachment] = []
    var initialPrompt: String = ""

    @State private var session: AssistantSession?
    @State private var input = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showImporter = false
    @State private var pickingNote = false
    @State private var setupNeeded = !AssistantPrefs.consented || Keychain.read(ClaudeClient.keyAccount) == nil
    @FocusState private var inputFocused: Bool

    private let quickPrompts = [
        ("Erklär mir das einfacher", "lightbulb"),
        ("Fass das als Notiz zusammen (in meiner Handschrift)", "doc.richtext"),
        ("Mach Karteikarten daraus", "rectangle.on.rectangle.angled"),
        ("Frag mich dazu ab – eine Frage nach der anderen", "questionmark.bubble"),
        ("Erstell mir eine kurze Probeklausur", "list.clipboard"),
        ("Was sollte ich als Nächstes lernen?", "map"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if setupNeeded {
                    AssistantSettingsView(onDone: { setupNeeded = false })
                } else if let session {
                    chat(session)
                } else {
                    ProgressView()
                }
            }
            .background(Palette.paper)
            .navigationTitle("Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                if !setupNeeded {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            session?.reset()
                            Haptics.tap()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Neues Gespräch")
                        .disabled(session?.busy ?? true)
                    }
                }
            }
        }
        .tint(Palette.marginRed)
        .onAppear {
            guard session == nil else { return }
            let created = AssistantSession(context: context)
            created.attachments = initialAttachments
            session = created
            input = initialPrompt
        }
        .onDisappear { session?.answerApproval(false) }
    }

    // MARK: Chat

    private func chat(_ session: AssistantSession) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if session.items.isEmpty {
                            intro(session)
                        }
                        ForEach(session.items) { item in
                            bubble(item)
                                .id(item.id)
                        }
                        if session.busy {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Claude denkt nach …")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                            .id("busy")
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.items.count) {
                    withAnimation { proxy.scrollTo(session.items.last?.id, anchor: .bottom) }
                }
            }

            if let approval = session.approval {
                approvalCard(approval, session: session)
            }
            composer(session)
        }
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task { await attachPhoto(item, to: session) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .plainText, .image, .rtf]) { result in
            if case .success(let url) = result { attachFile(url, to: session) }
        }
        .sheet(isPresented: $pickingNote) {
            NavigationStack {
                List(notes) { note in
                    Button {
                        session.attachments.append(AssistantAttachment(
                            title: note.title.isEmpty ? "Notiz" : note.title, symbol: "doc.text",
                            block: ClaudeClient.text("Notiz „\(note.title)“ aus Margin:\n\n\(note.body)")
                        ))
                        pickingNote = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(note.title.isEmpty ? "Ohne Titel" : note.title).foregroundStyle(Palette.ink)
                            Text(Fmt.date(note.noteDate)).font(.caption).foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
                .navigationTitle("Notiz anhängen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { pickingNote = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func intro(_ session: AssistantSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Woran arbeitest du?")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text("Häng ein Arbeitsblatt, ein PDF oder eine Notiz an – Claude arbeitet mit deinem Material und sagt dir, wenn etwas nicht darin steht.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            ForEach(quickPrompts, id: \.0) { prompt, symbol in
                Button {
                    input = prompt
                    send(session)
                } label: {
                    Label(prompt, systemImage: symbol)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ item: AssistantSession.Item) -> some View {
        switch item {
        case let .user(_, text, attachments):
            VStack(alignment: .trailing, spacing: 4) {
                if !attachments.isEmpty {
                    Label(attachments.joined(separator: ", "), systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                if !text.isEmpty {
                    Text(text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(Palette.paper)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 16))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        case let .assistant(_, text):
            Text(Self.markdown(text))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24)
        case let .action(_, label, ok):
            Label(ok ? label : "\(label) – abgelehnt", systemImage: ok ? "checkmark.circle" : "xmark.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(ok ? SubjectColor.green.color : Palette.secondaryInk)
        case let .notice(_, text):
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Palette.marginRed)
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func approvalCard(_ approval: AssistantSession.Approval, session: AssistantSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude möchte: \(approval.label)", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
            ScrollView {
                Text(approval.details)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            HStack {
                Button("Ablehnen") { session.answerApproval(false) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Erlauben") {
                    session.answerApproval(true)
                    Haptics.success()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
                .foregroundStyle(Palette.paper)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func composer(_ session: AssistantSession) -> some View {
        VStack(spacing: 8) {
            if !session.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(session.attachments) { attachment in
                            HStack(spacing: 4) {
                                Image(systemName: attachment.symbol)
                                Text(attachment.title).lineLimit(1)
                                Button {
                                    session.attachments.removeAll { $0.id == attachment.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .accessibilityLabel("Anhang entfernen")
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.sheet, in: Capsule())
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Foto (z. B. Arbeitsblatt)", systemImage: "photo")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("PDF oder Datei", systemImage: "doc")
                    }
                    Button {
                        pickingNote = true
                    } label: {
                        Label("Notiz aus Margin", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .accessibilityLabel("Material anhängen")

                TextField("Frag Claude …", text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 18))

                Button {
                    send(session)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend(session) ? Palette.ink : Palette.faintInk)
                }
                .disabled(!canSend(session))
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func canSend(_ session: AssistantSession) -> Bool {
        !session.busy && session.approval == nil
            && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.attachments.isEmpty)
    }

    private func send(_ session: AssistantSession) {
        let text = input
        input = ""
        inputFocused = false
        Task { await session.send(text) }
    }

    // MARK: Attachments

    private func attachPhoto(_ item: PhotosPickerItem, to session: AssistantSession) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
              let jpeg = Self.downsized(image).jpegData(compressionQuality: 0.8) else { return }
        session.attachments.append(AssistantAttachment(title: "Foto", symbol: "photo", block: ClaudeClient.image(jpeg: jpeg)))
    }

    private func attachFile(_ url: URL, to session: AssistantSession) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .pdf) {
            guard data.count < 30_000_000 else { return }
            session.attachments.append(AssistantAttachment(title: name, symbol: "doc.richtext", block: ClaudeClient.pdf(data, title: name)))
        } else if type.conforms(to: .image), let image = UIImage(data: data),
                  let jpeg = Self.downsized(image).jpegData(compressionQuality: 0.8) {
            session.attachments.append(AssistantAttachment(title: name, symbol: "photo", block: ClaudeClient.image(jpeg: jpeg)))
        } else if let text = String(data: data, encoding: .utf8) {
            session.attachments.append(AssistantAttachment(title: name, symbol: "doc.text",
                                                          block: ClaudeClient.text("Material „\(name)“:\n\n\(text)")))
        }
    }

    /// Scales a photo so its long side is at most 1568 px.
    static func downsized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > 1568 else { return image }
        let factor = 1568 / longest
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// API key, model, privacy. Shown before the first chat and in Settings.
struct AssistantSettingsView: View {
    var onDone: (() -> Void)?
    @State private var key = ""
    @State private var hasKey = Keychain.read(ClaudeClient.keyAccount) != nil
    @State private var consented = AssistantPrefs.consented
    @State private var model = AssistantPrefs.model
    @State private var confirmChanges = AssistantPrefs.confirmChanges
    @State private var useTools = AssistantPrefs.useTools

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude in Margin")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                    Text("Der Assistent ist freiwillig. Alles andere in Margin funktioniert ohne ihn und offline.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .marginRow()

            Section {
                Label("Wenn du Claude fragst, werden deine Nachricht, angehängtes Material (Fotos, PDFs, Notizen) und – falls erlaubt – die Margin-Daten, die Claude dafür abruft, an Anthropic gesendet.", systemImage: "arrow.up.forward.app")
                Label("Deine Handschriftproben werden nie gesendet.", systemImage: "signature")
                Label("Du brauchst einen eigenen API-Schlüssel von Anthropic. Die Nutzung wird über dein Anthropic-Konto abgerechnet.", systemImage: "creditcard")
                Toggle("Verstanden, ich möchte Claude nutzen", isOn: $consented)
            } header: {
                Text("Datenschutz")
            }
            .font(.subheadline)
            .marginRow()

            Section {
                if hasKey {
                    LabeledContent("API-Schlüssel", value: "gespeichert")
                    Button("Schlüssel entfernen", role: .destructive) {
                        Keychain.delete(ClaudeClient.keyAccount)
                        hasKey = false
                    }
                } else {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Schlüssel sichern") {
                        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        hasKey = Keychain.write(trimmed, account: ClaudeClient.keyAccount)
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    Link("Schlüssel erstellen auf console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.footnote)
                }
            } header: {
                Text("API-Schlüssel")
            } footer: {
                Text("Wird nur im iOS-Schlüsselbund dieses iPhones gespeichert – nicht im Code, nicht im Backup, nicht auf GitHub.")
            }
            .marginRow()

            Section {
                Picker("Modell", selection: $model) {
                    ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Margin-Daten lesen und nutzen", isOn: $useTools)
                Toggle("Vor jeder Änderung fragen", isOn: $confirmChanges)
            } footer: {
                Text("Mit Margin-Daten kann Claude z. B. deine Prüfungen und Themen sehen, Karteikarten und Notizen anlegen oder dein Verständnis nach einem Quiz eintragen.")
            }
            .marginRow()

            if let onDone {
                Section {
                    Button("Los geht's") {
                        save()
                        onDone()
                    }
                    .disabled(!consented || !hasKey)
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: save)
    }

    private func save() {
        AssistantPrefs.consented = consented
        AssistantPrefs.model = model
        AssistantPrefs.confirmChanges = confirmChanges
        AssistantPrefs.useTools = useTools
    }
}

/// Lets Claude Code or Claude Desktop on the PC use Margin as an MCP server.
struct MCPSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var server = MCPServer.shared
    @State private var showToken = false
    @State private var copied: String?

    var body: some View {
        Form {
            Section {
                Text("Während Margin geöffnet ist, kann Claude auf deinem PC (Claude Code oder Claude Desktop) im selben WLAN auf deine Schuldaten zugreifen – z. B. „Was steht diese Woche an?“ oder „Mach mir aus diesem Skript Karteikarten in Margin“.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .marginRow()

            Section {
                Toggle("Verbindung erlauben", isOn: Binding(
                    get: { server.isRunning },
                    set: { $0 ? server.start(context: context) : server.stop() }
                ))
                Toggle("Claude darf Änderungen machen", isOn: Binding(
                    get: { server.allowWrites }, set: { server.allowWrites = $0 }
                ))
                if let error = server.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Palette.marginRed)
                }
                if server.isRunning {
                    LabeledContent("Anfragen", value: "\(server.requestCount)")
                    if let last = server.lastActivity {
                        LabeledContent("Zuletzt", value: last)
                    }
                }
            } footer: {
                Text("Nur solange Margin offen ist (iOS erlaubt keinen Server im Hintergrund). Das Display bleibt dabei an. Ohne „Änderungen“ kann Claude nur lesen.")
            }
            .marginRow()

            Section {
                if let address = server.address {
                    copyRow("Adresse", value: address)
                } else {
                    Text("Keine WLAN-Adresse gefunden. Verbinde das iPhone mit dem WLAN deines PCs.")
                        .foregroundStyle(Palette.marginRed)
                }
                HStack {
                    Text("Zugangsschlüssel")
                    Spacer()
                    Text(showToken ? server.token : String(repeating: "•", count: 12))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(showToken ? "Verbergen" : "Zeigen") { showToken.toggle() }
                        .font(.caption)
                }
                Button("Neuen Schlüssel erzeugen", role: .destructive) {
                    server.regenerateToken()
                    Haptics.tap()
                }
            } header: {
                Text("Verbindung")
            }
            .marginRow()

            if let address = server.address {
                Section {
                    command(
                        "claude mcp add --transport http margin \(address) --header \"Authorization: Bearer \(server.token)\""
                    )
                } header: {
                    Text("Claude Code (Terminal auf dem PC)")
                } footer: {
                    Text("Einmal ausführen. Danach in Claude Code z. B. fragen: „Welche Aufgaben habe ich diese Woche in Margin?“")
                }
                .marginRow()

                Section {
                    command("""
                    {
                      "mcpServers": {
                        "margin": {
                          "command": "npx",
                          "args": ["-y", "mcp-remote", "\(address)", "--allow-http", "--header", "Authorization:${MARGIN_AUTH}"],
                          "env": { "MARGIN_AUTH": "Bearer \(server.token)" }
                        }
                      }
                    }
                    """)
                } header: {
                    Text("Claude Desktop (claude_desktop_config.json)")
                } footer: {
                    Text("Braucht Node.js auf dem PC. Danach Claude Desktop neu starten.")
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Claude verbinden")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copyRow(_ title: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copied = value
            Haptics.success()
        } label: {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    Text(value).font(.caption.monospaced()).lineLimit(1)
                    Image(systemName: copied == value ? "checkmark" : "doc.on.doc")
                }
            }
        }
    }

    private func command(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
