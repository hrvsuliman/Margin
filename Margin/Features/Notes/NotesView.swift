import PDFKit
import SwiftData
import SwiftUI

struct NotesView: View {
    enum Grouping: String, CaseIterable, Identifiable {
        case recent, subject, folder, exam
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recent: "Zuletzt bearbeitet"
            case .subject: "Nach Fach"
            case .folder: "Nach Ordner"
            case .exam: "Nach Prüfung"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \NoteDocument.updatedAt, order: .reverse) private var notes: [NoteDocument]
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query(sort: \HandwritingProfile.createdAt) private var profiles: [HandwritingProfile]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query private var noteImages: [NoteImage]

    @State private var path: [NoteDocument] = []
    @State private var recording = false
    @AppStorage("route.openNote") private var routeNote = ""
    @State private var search = ""
    @State private var grouping: Grouping = .recent
    @State private var renaming: NoteDocument?
    @State private var renameText = ""
    @State private var pendingDelete: NoteDocument?
    @State private var export: ExportFile?
    @State private var exporting = false

    private var filtered: [NoteDocument] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.body.localizedCaseInsensitiveContains(query)
                || note.folder.localizedCaseInsensitiveContains(query)
                || subjectName(note)?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if profiles.isEmpty {
                    Section {
                        NavigationLink {
                            ProfilesView()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Handschrift einrichten").foregroundStyle(Palette.ink)
                                    Text("Damit Notizen in deiner eigenen Schrift erscheinen.")
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondaryInk)
                                }
                            } icon: {
                                Image(systemName: "signature").foregroundStyle(Palette.marginRed)
                            }
                        }
                    }
                    .marginRow()
                }

                if notes.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "doc.text",
                            title: "Noch keine Notizen",
                            message: "Schreib, füge Text ein oder importiere ein PDF. Margin setzt es in deiner Handschrift auf Papier.",
                            actionTitle: "Neue Notiz",
                            action: newNote
                        )
                    }
                    .listRowBackground(Color.clear)
                } else if filtered.isEmpty {
                    Section {
                        Text("Keine Treffer für „\(search)“.")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .marginRow()
                } else {
                    ForEach(groups(), id: \.title) { group in
                        Section {
                            ForEach(group.notes) { note in
                                row(note)
                            }
                        } header: {
                            Text(group.title)
                        }
                        .marginRow()
                    }
                }
            }
            .marginList()
            .searchable(text: $search, prompt: "Notizen durchsuchen")
            .navigationTitle("Notizen")
            .navigationDestination(for: NoteDocument.self) { note in
                NoteEditorView(document: note)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ProfilesView()
                    } label: {
                        Image(systemName: "signature")
                    }
                    .accessibilityLabel("Handschrift")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Ordnen", selection: $grouping) {
                            ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Ordnen")
                    Menu {
                        Button(action: newNote) {
                            Label("Neue Notiz", systemImage: "square.and.pencil")
                        }
                        Button {
                            recording = true
                        } label: {
                            Label("Stunde aufnehmen", systemImage: "waveform")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    } primaryAction: {
                        newNote()
                    }
                    .accessibilityLabel("Neue Notiz")
                }
            }
            .alert("Umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Titel", text: $renameText)
                Button("Sichern") {
                    renaming?.title = renameText
                    renaming?.updatedAt = .now
                    try? context.save()
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog("Notiz löschen?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { note in
                Button("Löschen", role: .destructive) {
                    context.delete(note)
                    try? context.save()
                }
            } message: { note in
                Text("„\(note.title.isEmpty ? "Ohne Titel" : note.title)“ wird endgültig gelöscht.")
            }
            .fullScreenCover(isPresented: $recording) {
                RecordingView { note in path.append(note) }
            }
            .onChange(of: routeNote, initial: true) {
                guard !routeNote.isEmpty else { return }
                if let note = notes.first(where: { $0.uid.uuidString == routeNote }) { path.append(note) }
                routeNote = ""
            }
            .sheet(item: $export) { file in
                NavigationStack { ExportPreviewView(file: file) }
                    .tint(Palette.marginRed)
            }
            .overlay {
                if exporting {
                    ProgressView("PDF wird erstellt …")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func row(_ note: NoteDocument) -> some View {
        NavigationLink(value: note) {
            NoteRow(note: note, subject: subjectName(note))
        }
        .contextMenu {
            Button {
                renameText = note.title
                renaming = note
            } label: {
                Label("Umbenennen", systemImage: "pencil")
            }
            Button {
                duplicate(note)
            } label: {
                Label("Duplizieren", systemImage: "plus.square.on.square")
            }
            Button {
                exportPDF(note)
            } label: {
                Label("Als PDF teilen", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                pendingDelete = note
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                pendingDelete = note
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    // MARK: Grouping

    private struct NoteGroup {
        let title: String
        let notes: [NoteDocument]
    }

    private func subjectName(_ note: NoteDocument) -> String? {
        note.subjectUID.flatMap { uid in subjects.first { $0.uid == uid }?.name }
    }

    private func groups() -> [NoteGroup] {
        let list = filtered
        switch grouping {
        case .recent:
            return [NoteGroup(title: "Zuletzt bearbeitet", notes: list)]
        case .subject:
            var result = subjects.compactMap { subject -> NoteGroup? in
                let matches = list.filter { $0.subjectUID == subject.uid }
                return matches.isEmpty ? nil : NoteGroup(title: subject.name, notes: matches)
            }
            let known = Set(subjects.map(\.uid))
            let other = list.filter { $0.subjectUID.map { !known.contains($0) } ?? true }
            if !other.isEmpty { result.append(NoteGroup(title: "Ohne Fach", notes: other)) }
            return result
        case .folder:
            let names = Array(Set(list.map(\.folder))).sorted { a, b in
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                return a.localizedCompare(b) == .orderedAscending
            }
            return names.map { name in
                NoteGroup(title: name.isEmpty ? "Ohne Ordner" : name, notes: list.filter { $0.folder == name })
            }
        case .exam:
            var result = exams.compactMap { exam -> NoteGroup? in
                let matches = list.filter { $0.examUID == exam.uid }
                return matches.isEmpty ? nil : NoteGroup(title: "\(exam.displayTitle) · \(Fmt.dayMonth(exam.date))", notes: matches)
            }
            let known = Set(exams.map(\.uid))
            let other = list.filter { $0.examUID.map { !known.contains($0) } ?? true }
            if !other.isEmpty { result.append(NoteGroup(title: "Ohne Prüfung", notes: other)) }
            return result
        }
    }

    // MARK: Actions

    private func newNote() {
        let note = NoteDocument(title: "")
        note.profileUID = nil
        context.insert(note)
        try? context.save()
        path.append(note)
    }

    private func duplicate(_ note: NoteDocument) {
        let copy = NoteDocument(title: note.title.isEmpty ? "Kopie" : "\(note.title) (Kopie)")
        copy.body = note.body
        copy.folder = note.folder
        copy.noteDate = note.noteDate
        copy.subjectUID = note.subjectUID
        copy.topicUID = note.topicUID
        copy.examUID = note.examUID
        copy.profileUID = note.profileUID
        copy.paperRaw = note.paperRaw
        copy.lineSpacingMM = note.lineSpacingMM
        copy.writingSize = note.writingSize
        copy.penColorRaw = note.penColorRaw
        copy.penWeight = note.penWeight
        copy.marginTopMM = note.marginTopMM
        copy.marginBottomMM = note.marginBottomMM
        copy.marginLeftMM = note.marginLeftMM
        copy.marginRightMM = note.marginRightMM
        copy.showMarginLine = note.showMarginLine
        copy.showPageNumbers = note.showPageNumbers
        copy.showHeader = note.showHeader
        copy.printPaper = note.printPaper
        copy.seed = note.seed
        copy.thumbnail = note.thumbnail
        context.insert(copy)
        try? context.save()
        Haptics.success()
    }

    private func exportPDF(_ note: NoteDocument) {
        exporting = true
        Task {
            let data = await NoteRendering.pdf(for: note, subjects: subjects, profiles: profiles, images: noteImages)
            let title = note.title.isEmpty ? "Notiz" : note.title
            if let url = try? NoteRendering.temporaryPDF(data, title: title) {
                let pages = PDFPageCounter.count(url)
                export = ExportFile(url: url, title: title, pageCount: pages)
            }
            exporting = false
        }
    }
}

private struct NoteRow: View {
    let note: NoteDocument
    let subject: String?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? "Ohne Titel" : note.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text([subject, Fmt.date(note.noteDate), note.folder.isEmpty ? nil : note.folder]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                let snippet = note.body.split(separator: "\n").first.map(String.init) ?? ""
                if !snippet.isEmpty {
                    Text(LineStyle.strip(snippet))
                        .font(.caption)
                        .foregroundStyle(Palette.faintInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = note.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                PaperInk.paper
                VStack(spacing: 5) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle().fill(PaperInk.guideFaint).frame(height: 0.8)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

enum PDFPageCounter {
    static func count(_ url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }
}
