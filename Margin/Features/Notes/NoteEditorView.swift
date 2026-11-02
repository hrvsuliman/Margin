import PhotosUI
import SwiftData
import SwiftUI

/// Edit a note as text and see it as handwritten pages. The text is the
/// source; the pages are re-rendered from it after every change.
struct NoteEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case text, pages
        var id: String { rawValue }
        var title: String { self == .text ? "Text" : "Handschrift" }
    }

    @Environment(\.modelContext) private var context
    @Bindable var document: NoteDocument
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query(sort: \HandwritingProfile.createdAt) private var profiles: [HandwritingProfile]
    @Query private var noteImages: [NoteImage]

    @State private var mode: Mode
    @StateObject private var textController = MarkupTextController()
    @State private var pages: [LaidOutPage] = []
    @State private var renderedSettings = PageSettings()
    @State private var isRendering = false
    @State private var showDetails = false
    @State private var showPageSettings = false
    @State private var showImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var export: ExportFile?
    @State private var imageItem: PhotosPickerItem?
    @State private var showOCRPhotos = false
    @State private var showGluePhotos = false
    @State private var camera: CameraPurpose?

    enum CameraPurpose: String, Identifiable {
        case ocr, glue
        var id: String { rawValue }
    }
    @State private var showImages = false
    @State private var showAssistant = false
    @State private var imageExport: ImageExport?

    private var myImages: [NoteImage] { noteImages.filter { $0.noteUID == document.uid } }

    init(document: NoteDocument) {
        self.document = document
        _mode = State(initialValue: document.body.isEmpty ? .text : .pages)
    }

    private var profile: HandwritingProfile? { NoteRendering.profile(for: document, in: profiles) }

    private struct RenderKey: Equatable {
        var content: NoteContent
        var settings: PageSettings
        var profileUID: UUID?
        var profileRevision: Date?
    }

    private var renderKey: RenderKey {
        RenderKey(
            content: NoteRendering.content(for: document, subjects: subjects, images: noteImages),
            settings: PageSettings(document: document),
            profileUID: profile?.uid,
            profileRevision: profile?.updatedAt
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch mode {
            case .text: textEditor
            case .pages: pagesView
            }
        }
        .background(Palette.paper)
        .navigationTitle(document.title.isEmpty ? "Neue Notiz" : document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task(id: renderKey) { await render() }
        .onChange(of: document.body) { document.updatedAt = .now }
        .onChange(of: document.title) { document.updatedAt = .now }
        .onDisappear(perform: saveThumbnail)
        .sheet(isPresented: $showDetails) {
            NavigationStack { NoteDetailsView(document: document) }
                .tint(Palette.marginRed)
        }
        .sheet(isPresented: $showPageSettings) {
            NavigationStack { NoteSettingsView(document: document) }
                .tint(Palette.marginRed)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(item: $export) { file in
            NavigationStack { ExportPreviewView(file: file) }
                .tint(Palette.marginRed)
        }
        .photosPicker(isPresented: $showOCRPhotos, selection: $photoItem, matching: .images)
        .photosPicker(isPresented: $showGluePhotos, selection: $imageItem, matching: .images)
        .fullScreenCover(item: $camera) { purpose in
            CameraPicker { image in
                camera = nil
                switch purpose {
                case .ocr:
                    runImport { try await TextImport.text(from: image) }
                case .glue:
                    Task { await glue(image) }
                }
            } onCancel: {
                camera = nil
            }
            .ignoresSafeArea()
        }
        .sheet(item: $imageExport) { export in
            NavigationStack { ImageExportView(export: export) }
                .tint(Palette.marginRed)
        }
        .sheet(isPresented: $showAssistant) {
            AssistantView(initialAttachments: [AssistantAttachment(
                title: document.title.isEmpty ? "Diese Notiz" : document.title, symbol: "doc.text",
                block: ClaudeClient.text("Notiz „\(document.title)“ aus Margin (id \(document.uid.uuidString)):\n\n\(document.body)"),
                text: document.body
            )])
        }
        .sheet(isPresented: $showImages) {
            NavigationStack { NoteImagesView(document: document) }
                .tint(Palette.marginRed)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: imageItem) {
            guard let item = imageItem else { return }
            imageItem = nil
            Task { await insertImage(item) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: TextImport.supportedTypes) { result in
            if case .success(let url) = result {
                runImport { try await TextImport.text(from: url) }
            }
        }
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            runImport {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    throw TextImportError.noText
                }
                return try await TextImport.text(from: image)
            }
        }
        .alert("Import nicht möglich", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if importing {
                ProgressView("Text wird erkannt …")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: Text

    private var textEditor: some View {
        VStack(spacing: 0) {
            TextField("Titel", text: $document.title, axis: .vertical)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .padding(.horizontal, 17)
                .padding(.top, 4)
            Button {
                showDetails = true
            } label: {
                HStack(spacing: 6) {
                    Text(NoteRendering.header(for: document, subjects: subjects))
                    if !document.folder.isEmpty {
                        Text("· \(document.folder)")
                    }
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Palette.ruling).frame(height: 1)
            MarkupTextView(text: $document.body, controller: textController)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button { textController.apply(.heading) } label: { Image(systemName: "textformat.size.larger") }
                    .accessibilityLabel("Überschrift")
                Button { textController.apply(.subheading) } label: { Image(systemName: "textformat") }
                    .accessibilityLabel("Zwischenüberschrift")
                Button { textController.apply(.bullet) } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Aufzählung")
                Button { textController.apply(.plain) } label: { Image(systemName: "text.alignleft") }
                    .accessibilityLabel("Normaler Text")
                Spacer()
                Button { textController.endEditing() } label: { Image(systemName: "keyboard.chevron.compact.down") }
                    .accessibilityLabel("Tastatur ausblenden")
            }
        }
    }

    // MARK: Pages

    private var pagesView: some View {
        ScrollView {
            VStack(spacing: 14) {
                if profile == nil {
                    banner(
                        "Noch keine Handschrift eingerichtet. Bis dahin wird eine Ersatzschrift verwendet.",
                        action: "Einrichten"
                    )
                } else if pages.contains(where: { !$0.fallbacks.isEmpty }) {
                    banner(
                        "Einige Zeichen fehlen in deiner Handschrift und erscheinen in einer Ersatzschrift.",
                        action: "Zeichen ergänzen"
                    )
                }
                LazyVStack(spacing: 18) {
                    ForEach(pages, id: \.number) { page in
                        PageCanvas(page: page, settings: renderedSettings)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(page.number)/\(pages.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                            }
                    }
                }
                .opacity(isRendering && pages.isEmpty ? 0 : 1)
            }
            .padding(16)
            .animation(.easeInOut(duration: 0.25), value: pages.count)
        }
        .overlay {
            if isRendering && pages.isEmpty { ProgressView() }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    document.seed = Int.random(in: 1...999_999)
                    Haptics.tap()
                } label: {
                    Label("Neu mischen", systemImage: "dice")
                }
                Spacer()
                Button {
                    showPageSettings = true
                } label: {
                    Label("Papier & Stift", systemImage: "slider.horizontal.3")
                }
                Menu {
                    Button {
                        exportPDF()
                    } label: {
                        Label("Als PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        exportImages()
                    } label: {
                        Label("Als Bilder (eine pro Seite)", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
                .foregroundStyle(Palette.paper)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func banner(_ text: String, action: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "signature").foregroundStyle(Palette.marginRed)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.footnote).foregroundStyle(Palette.ink)
                NavigationLink {
                    if let profile {
                        ProfileDetailView(profile: profile)
                    } else {
                        ProfilesView()
                    }
                } label: {
                    Text(action).font(.footnote.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button {
                    showImporter = true
                } label: {
                    Label("PDF, Text oder Bild", systemImage: "doc")
                }
                Section("Text erkennen") {
                    if CameraPicker.isAvailable {
                        Button {
                            camera = .ocr
                        } label: {
                            Label("Tafel fotografieren", systemImage: "camera.viewfinder")
                        }
                    }
                    Button {
                        showOCRPhotos = true
                    } label: {
                        Label("Foto aus der Mediathek", systemImage: "text.viewfinder")
                    }
                }
                Section("Bild einkleben") {
                    if CameraPicker.isAvailable {
                        Button {
                            camera = .glue
                        } label: {
                            Label("Foto aufnehmen", systemImage: "camera")
                        }
                    }
                    Button {
                        showGluePhotos = true
                    } label: {
                        Label("Aus der Mediathek", systemImage: "photo.badge.plus")
                    }
                }
                if !myImages.isEmpty {
                    Button {
                        showImages = true
                    } label: {
                        Label("Bilder (\(myImages.count))", systemImage: "photo.on.rectangle")
                    }
                }
                Button {
                    if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                        appendToBody(TextImport.clean(pasted))
                        mode = .text
                    }
                } label: {
                    Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Text importieren")

            Button {
                showAssistant = true
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityLabel("Claude zu dieser Notiz fragen")

            Button {
                showDetails = true
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("Details")
        }
    }

    // MARK: Actions

    private func render() async {
        let key = renderKey
        isRendering = true
        // Wait until typing pauses.
        try? await Task.sleep(nanoseconds: pages.isEmpty ? 0 : 300_000_000)
        guard !Task.isCancelled else { return }
        let source = profile.map { FontSource(profile: $0) } ?? .empty
        let result = await NoteRendering.render(content: key.content, settings: key.settings, source: source)
        guard !Task.isCancelled else { return }
        renderedSettings = key.settings
        pages = result
        isRendering = false
    }

    private func runImport(_ work: @escaping () async throws -> String) {
        importing = true
        Task {
            do {
                let text = try await work()
                appendToBody(text)
                mode = .text
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
            }
            importing = false
        }
    }

    /// Stores the picture and adds a `[[Bild:…]]` line where it should appear.
    private func insertImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            errorMessage = "Das Bild konnte nicht geladen werden."
            return
        }
        await glue(image)
    }

    private func glue(_ image: UIImage) async {
        do {
            guard let jpeg = image.jpegForStorage() else { throw TextImportError.noText }
            let stored = try AttachmentStore.store(jpeg, fileName: "bild.jpg")
            let noteImage = NoteImage(noteUID: document.uid, storedName: stored.storedName)
            context.insert(noteImage)
            appendToBody(NoteBlock.imageLine(noteImage.uid))
            try? context.save()
            mode = .pages
            Haptics.success()
        } catch {
            errorMessage = "Das Bild konnte nicht eingefügt werden."
        }
    }

    private func appendToBody(_ text: String) {
        let separator = document.body.isEmpty ? "" : (document.body.hasSuffix("\n") ? "\n" : "\n\n")
        document.body += separator + text
    }

    private func exportPDF() {
        let settings = renderedSettings
        let currentPages = pages
        let title = document.title.isEmpty ? "Notiz" : document.title
        Task {
            let data = await Task.detached(priority: .userInitiated) {
                PageRenderer.pdf(pages: currentPages, settings: settings, title: title)
            }.value
            do {
                let url = try NoteRendering.temporaryPDF(data, title: title)
                export = ExportFile(url: url, title: title, pageCount: currentPages.count)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Each page as a sharp PNG (3× A4 points), ready for Photos, WhatsApp or AirDrop.
    private func exportImages() {
        let settings = renderedSettings
        let currentPages = pages
        let title = document.title.isEmpty ? "Notiz" : document.title
        Task {
            let urls = await Task.detached(priority: .userInitiated) { () -> [URL] in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Bilder-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return currentPages.compactMap { page in
                    let image = PageRenderer.thumbnail(of: page, settings: settings, width: settings.pageSize.width * 1.5)
                    guard let data = image.pngData() else { return nil }
                    let name = currentPages.count == 1 ? "\(title).png" : "\(title) – Seite \(page.number).png"
                    let url = folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
                    return (try? data.write(to: url)) != nil ? url : nil
                }
            }.value
            imageExport = ImageExport(urls: urls, title: title)
        }
    }

    private func saveThumbnail() {
        LearningStore.syncCards(for: document, context: context)
        if let first = pages.first {
            document.thumbnail = PageRenderer.thumbnail(of: first, settings: renderedSettings, width: 120)
                .jpegData(compressionQuality: 0.75)
        }
        try? context.save()
    }
}

/// One A4 page drawn at the width available.
struct PageCanvas: View {
    let page: LaidOutPage
    let settings: PageSettings

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                let scale = size.width / settings.pageSize.width
                cg.scaleBy(x: scale, y: scale)
                PageRenderer.draw(page, settings: settings, in: cg, includePaper: true)
            }
        }
        .aspectRatio(settings.pageSize.width / settings.pageSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Seite \(page.number)")
    }
}
