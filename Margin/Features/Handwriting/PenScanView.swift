import PDFKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Handwriting from pen and paper: print the template, fill it in,
/// scan it, check what was found, save.
struct PenScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let profile: HandwritingProfile

    @State private var templateFile: ExportFile?
    @State private var showCamera = false
    @State private var showImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var processing = false
    @State private var results: [TemplateScanner.PageResult] = []
    @State private var problems: [String] = []
    @State private var showReview = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mit deinem eigenen Stift")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                    Text("Du schreibst auf Papier, wie immer. Margin schneidet jedes Zeichen aus dem Scan aus – so sieht der Text wirklich nach deiner Handschrift aus.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.vertical, 4)
            }
            .marginRow()

            Section {
                step(1, "Vorlage drucken", detail: "2 Seiten A4. Teilen › Drucken, oder in Dateien sichern und z. B. in der Schule drucken.") {
                    makeTemplate()
                }
                step(2, "Mit deinem Stift ausfüllen", detail: "Ein Zeichen pro Kästchen, auf der durchgezogenen Linie. Blau oder schwarz, kein Bleistift.", action: nil)
                step(3, "Mit der Kamera scannen", detail: "Beide Seiten nacheinander. Die Kamera erkennt die Seite und richtet sie gerade aus.") {
                    showCamera = true
                }
                .disabled(!VNDocumentCameraViewController.isSupported)
            } header: {
                Text("So geht's")
            }
            .marginRow()

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Scan als PDF oder Bild aus Dateien", systemImage: "doc.viewfinder")
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 2, matching: .images) {
                    Label("Foto aus der Mediathek", systemImage: "photo")
                }
            } header: {
                Text("Schon gescannt?")
            } footer: {
                Text("Die Bilder werden nur auf diesem iPhone ausgewertet und nicht gespeichert.")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Stift & Papier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
            }
        }
        .sheet(item: $templateFile) { file in
            NavigationStack { ExportPreviewView(file: file) }
                .tint(Palette.marginRed)
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView { images in
                showCamera = false
                process(images.compactMap(\.cgImage), photos: false)
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            process(urls: urls)
        }
        .onChange(of: photoItems) {
            let items = photoItems
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                var images: [CGImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data).flatMap(Self.upright) {
                        images.append(image)
                    }
                }
                process(images, photos: true)
            }
        }
        .navigationDestination(isPresented: $showReview) {
            ScanReviewView(profile: profile, results: results, problems: problems) {
                dismiss()
            }
        }
        .overlay {
            if processing {
                ProgressView("Vorlage wird ausgewertet …")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func step(_ number: Int, _ title: String, detail: String, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Palette.paper)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(action == nil ? Palette.faintInk : Palette.ink))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Palette.ink)
                    Text(detail).font(.caption).foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.faintInk)
                }
            }
        }
        .disabled(action == nil)
    }

    // MARK: Actions

    private func makeTemplate() {
        do {
            let url = try NoteRendering.temporaryPDF(HandwritingTemplate.pdf(), title: "Margin Handschrift-Vorlage")
            templateFile = ExportFile(url: url, title: "Handschrift-Vorlage", pageCount: HandwritingTemplate.pages.count)
        } catch {
            problems = [error.localizedDescription]
        }
    }

    private func process(urls: [URL]) {
        var images: [CGImage] = []
        var photos: [CGImage] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true, let pdf = PDFDocument(url: url) {
                for index in 0..<min(pdf.pageCount, 4) {
                    guard let page = pdf.page(at: index) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    let scale = 2400 / max(bounds.width, bounds.height, 1)
                    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                    if let image = page.thumbnail(of: size, for: .mediaBox).cgImage { images.append(image) }
                }
            } else if let image = UIImage(contentsOfFile: url.path).flatMap(Self.upright) {
                photos.append(image)
            }
        }
        process(images, photos: false, morePhotos: photos)
    }

    /// Scans are already straight; photos get straightened first.
    private func process(_ images: [CGImage], photos: Bool, morePhotos: [CGImage] = []) {
        let all = images.map { ($0, photos) } + morePhotos.map { ($0, true) }
        guard !all.isEmpty else { return }
        processing = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ([TemplateScanner.PageResult], [String]) in
                var pages: [TemplateScanner.PageResult] = []
                var errors: [String] = []
                for (index, entry) in all.enumerated() {
                    let image = entry.1 ? TemplateScanner.straightenedPage(entry.0) : entry.0
                    do {
                        pages.append(try TemplateScanner.scan(image, preferredPage: index + 1))
                    } catch {
                        errors.append("Bild \(index + 1): \(error.localizedDescription)")
                    }
                }
                return (pages, errors)
            }.value
            results = outcome.0
            problems = outcome.1
            processing = false
            showReview = true
        }
    }

    /// Draws a photo upright (camera photos often store their rotation separately).
    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }
}

/// Everything found on the scanned pages; untick anything that went wrong.
struct ScanReviewView: View {
    @Environment(\.modelContext) private var context
    let profile: HandwritingProfile
    let results: [TemplateScanner.PageResult]
    let problems: [String]
    let onDone: () -> Void

    @State private var excluded: Set<UUID> = []
    @State private var replaceExisting = true
    @State private var saved = false

    private var glyphs: [TemplateScanner.Glyph] { results.flatMap(\.glyphs) }
    private var characterGlyphs: [TemplateScanner.Glyph] {
        glyphs.filter { if case .character = $0.item { return true } else { return false } }
    }
    private var wordGlyph: TemplateScanner.Glyph? {
        glyphs.first { if case .sampleWord = $0.item { return true } else { return false } }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Seiten", value: "\(results.count)")
                LabeledContent("Zeichen gefunden", value: "\(characterGlyphs.count)")
                LabeledContent("Leere Kästchen", value: "\(results.reduce(0) { $0 + $1.emptyBoxes })")
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.marginRed)
                }
            }
            .marginRow()

            if !characterGlyphs.isEmpty {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(characterGlyphs) { glyph in
                            Button {
                                if excluded.contains(glyph.id) { excluded.remove(glyph.id) } else { excluded.insert(glyph.id) }
                                Haptics.selection()
                            } label: {
                                GlyphTile(variant: Self.variant(glyph), character: glyph.item.text)
                                    .aspectRatio(0.9, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .opacity(excluded.contains(glyph.id) ? 0.25 : 1)
                                    .overlay(alignment: .bottomTrailing) {
                                        Text(glyph.item.text)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Palette.secondaryInk)
                                            .padding(3)
                                    }
                                    .overlay {
                                        if excluded.contains(glyph.id) {
                                            Image(systemName: "xmark").foregroundStyle(Palette.marginRed)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(glyph.item.text), \(excluded.contains(glyph.id) ? "ausgelassen" : "übernehmen")")
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Erkannte Zeichen")
                } footer: {
                    Text("Tippe auf ein Zeichen, das falsch ausgeschnitten wurde, um es auszulassen. Den Buchstaben unten rechts hat Margin dem Kästchen zugeordnet.")
                }
                .marginRow()
            }

            if let wordGlyph {
                Section("Probewort") {
                    GlyphTile(variant: Self.variant(wordGlyph), character: wordGlyph.item.text)
                        .frame(height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .marginRow()
            }

            Section {
                Toggle("Bisherige Proben dieser Zeichen ersetzen", isOn: $replaceExisting)
                Button {
                    save()
                } label: {
                    Text(saved ? "Gespeichert" : "Übernehmen")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(characterGlyphs.isEmpty || saved)
            } footer: {
                Text("Mit dem Finger geschriebene Zeichen werden durch die Stift-Versionen ersetzt. Ausgelassene Zeichen kannst du später einzeln nachholen.")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Prüfen")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func variant(_ glyph: TemplateScanner.Glyph) -> HandwritingFont.Variant? {
        let input = GlyphInput(uid: glyph.id, strokes: [], scale: 1, baselineOffset: 0, outlines: glyph.outlines)
        return HandwritingFont.makeVariant(input, analysis: HandwritingAnalysis(), penRatio: 0.15)
    }

    private func save() {
        var replaced: Set<String> = []
        for glyph in characterGlyphs where !excluded.contains(glyph.id) {
            guard case .character(let character) = glyph.item else { continue }
            if replaceExisting && !replaced.contains(character) {
                for old in profile.samples(for: character) { context.delete(old) }
                replaced.insert(character)
            }
            let sample = GlyphSample(character: character, strokeData: GlyphStrokes.encodeOutlines(glyph.outlines))
            context.insert(sample)
            sample.profile = profile
        }
        try? context.save()

        if let wordGlyph, case .sampleWord(let word) = wordGlyph.item,
           let gap = HandwritingAnalysis.letterSpacing(word: word, written: wordGlyph.outlines,
                                                       glyphs: FontSource(profile: profile).glyphs) {
            profile.letterSpacing = gap
            profile.spacingMeasured = true
        }
        profile.touch()
        try? context.save()
        saved = true
        Haptics.success()
        Deferred.afterDismiss { onDone() }
    }
}

/// Apple's document camera: finds the page edges and straightens the photo.
struct DocumentCameraView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}
