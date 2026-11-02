import PDFKit
import SwiftData
import SwiftUI

/// Paper, pen and layout of a note. Changes show live on the pages behind the sheet.
struct NoteSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var document: NoteDocument

    var body: some View {
        Form {
            Section("Papier") {
                Picker("Papier", selection: $document.paperRaw) {
                    ForEach(PaperStyle.allCases) { paper in
                        Label(paper.title, systemImage: paper.symbol).tag(paper.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleOnly)
                Stepper(value: $document.lineSpacingMM, in: 5...14, step: 0.5) {
                    LabeledContent("Zeilenabstand", value: String(format: "%.1f mm", document.lineSpacingMM))
                }
                Toggle("Korrekturrand", isOn: $document.showMarginLine)
                Toggle("Linien im PDF drucken", isOn: $document.printPaper)
            }
            .marginRow()

            Section("Schrift") {
                VStack(alignment: .leading) {
                    LabeledContent("Schriftgröße", value: "\(Int((document.writingSize * 100).rounded())) %")
                    Slider(value: $document.writingSize, in: 0.7...1.4, step: 0.05)
                }
                VStack(alignment: .leading) {
                    LabeledContent("Stiftstärke", value: "\(Int((document.penWeight * 100).rounded())) %")
                    Slider(value: $document.penWeight, in: 0.6...1.8, step: 0.05)
                }
                HStack(spacing: 12) {
                    ForEach(PenColor.allCases) { pen in
                        Button {
                            document.penColor = pen
                            Haptics.selection()
                        } label: {
                            Circle()
                                .fill(Color(uiColor: UIColor(hex: pen.hex)))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if document.penColor == pen {
                                        Circle().stroke(Palette.ink, lineWidth: 2).padding(-4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pen.title)
                        .accessibilityAddTraits(document.penColor == pen ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .marginRow()

            Section("Ränder") {
                marginStepper("Oben", value: $document.marginTopMM)
                marginStepper("Unten", value: $document.marginBottomMM)
                marginStepper("Links", value: $document.marginLeftMM)
                marginStepper("Rechts", value: $document.marginRightMM)
            }
            .marginRow()

            Section("Seite") {
                Toggle("Fach und Datum oben", isOn: $document.showHeader)
                Toggle("Seitenzahlen", isOn: $document.showPageNumbers)
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Papier & Stift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .onChange(of: document.paperRaw) {
            document.lineSpacingMM = document.paper.defaultLineSpacing
        }
        .onDisappear { try? context.save() }
    }

    private func marginStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 5...45, step: 5) {
            LabeledContent(title, value: "\(Int(value.wrappedValue)) mm")
        }
    }
}

/// Title, subject, folder, date and handwriting of a note.
struct NoteDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var document: NoteDocument
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query(sort: \HandwritingProfile.createdAt) private var profiles: [HandwritingProfile]
    @Query private var notes: [NoteDocument]

    private var subject: SchoolSubject? {
        document.subjectUID.flatMap { uid in subjects.first { $0.uid == uid } }
    }

    private var folders: [String] {
        Array(Set(notes.map(\.folder).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        Form {
            Section {
                TextField("Titel", text: $document.title)
                DatePicker("Datum", selection: $document.noteDate, displayedComponents: .date)
            }
            .marginRow()

            Section("Zuordnung") {
                Picker("Fach", selection: $document.subjectUID) {
                    Text("Kein Fach").tag(nil as UUID?)
                    ForEach(subjects) { subject in
                        Text(subject.name).tag(subject.uid as UUID?)
                    }
                }
                if let subject, !(subject.topics ?? []).isEmpty {
                    Picker("Thema", selection: $document.topicUID) {
                        Text("Kein Thema").tag(nil as UUID?)
                        ForEach(TopicOutline.flatten(subject.rootTopics), id: \.topic.uid) { entry in
                            Text(String(repeating: "   ", count: entry.depth) + entry.topic.title)
                                .tag(entry.topic.uid as UUID?)
                        }
                    }
                }
                Picker("Prüfung", selection: $document.examUID) {
                    Text("Keine Prüfung").tag(nil as UUID?)
                    ForEach(exams.filter { subject == nil || $0.subject == subject }) { exam in
                        Text("\(exam.displayTitle) · \(Fmt.dayMonth(exam.date))").tag(exam.uid as UUID?)
                    }
                }
            }
            .marginRow()

            Section {
                TextField("Ordner, z. B. Abiturvorbereitung", text: $document.folder)
                if !folders.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(folders, id: \.self) { folder in
                                Button(folder) { document.folder = folder }
                                    .buttonStyle(.bordered)
                                    .tint(document.folder == folder ? Palette.marginRed : Palette.secondaryInk)
                                    .font(.caption)
                            }
                        }
                    }
                }
            } header: {
                Text("Ordner")
            }
            .marginRow()

            Section {
                Picker("Handschrift", selection: $document.profileUID) {
                    Text("Standard").tag(nil as UUID?)
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.uid as UUID?)
                    }
                }
            } footer: {
                Text("Der Text bleibt immer erhalten. Die Handschrift wird bei jeder Änderung neu gesetzt.")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .onChange(of: document.subjectUID) {
            document.topicUID = nil
        }
        .onDisappear {
            document.updatedAt = .now
            try? context.save()
        }
    }
}

/// The pictures glued into a note: caption, size, remove.
struct NoteImagesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: NoteDocument
    @Query(sort: \NoteImage.createdAt) private var allImages: [NoteImage]

    private var images: [NoteImage] { allImages.filter { $0.noteUID == document.uid } }

    var body: some View {
        List {
            ForEach(images) { image in
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        if let cg = NoteImageLoader.image(at: AttachmentStore.directory.appendingPathComponent(image.storedName), maxPixels: 300) {
                            Image(decorative: cg, scale: 1)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        VStack(alignment: .leading) {
                            TextField("Bildunterschrift (optional)", text: Binding(
                                get: { image.caption }, set: { image.caption = $0; touch() }
                            ))
                            Stepper(value: Binding(get: { image.heightLines }, set: { image.heightLines = $0; touch() }), in: 3...16) {
                                Text("Höhe: \(image.heightLines) Zeilen").font(.subheadline)
                            }
                        }
                    }
                    Button("Bild entfernen", role: .destructive) { remove(image) }
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Bilder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
    }

    private func touch() {
        document.updatedAt = .now
        try? context.save()
    }

    private func remove(_ image: NoteImage) {
        let line = NoteBlock.imageLine(image.uid)
        document.body = document.body
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces) != line }
            .joined(separator: "\n")
        try? FileManager.default.removeItem(at: AttachmentStore.directory.appendingPathComponent(image.storedName))
        context.delete(image)
        touch()
    }
}

/// A finished PDF, ready to look at and share.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let pageCount: Int
}

struct ExportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let file: ExportFile

    var body: some View {
        PDFKitView(url: file.url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(file.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: file.url, preview: SharePreview(file.title)) {
                        Label("Teilen oder sichern", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .status) {
                    Text("\(file.pageCount) Seite\(file.pageCount == 1 ? "" : "n") · A4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

/// PDFKit's viewer with pinch-to-zoom.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(Palette.paper)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
