import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Progress towards the next exam

/// "Bis zur Arbeit": countdown, readiness, topics that sit, sessions done, and time learned this week.
struct SubjectProgressSection: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [StudySession]
    let subject: SchoolSubject
    var addExam: () -> Void

    private var nextExam: Exam? {
        let today = Calendar.school.startOfDay(for: .now)
        return (subject.exams ?? []).filter { $0.date >= today }.min { $0.date < $1.date }
    }

    private var minutesThisWeek: Int {
        let calendar = Calendar.school
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return sessions
            .filter { $0.subjectUID == subject.uid && $0.status == .done }
            .filter { week.contains($0.completedAt ?? $0.date) }
            .reduce(0) { $0 + max($1.actualMinutes, 0) }
    }

    var body: some View {
        Section {
            if let exam = nextExam {
                NavigationLink {
                    ExamDetailView(exam: exam)
                } label: {
                    examCard(exam)
                }
            } else {
                Button(action: addExam) {
                    Label("Nächste Arbeit eintragen – Margin plant das Lernen", systemImage: "calendar.badge.plus")
                }
            }
            if minutesThisWeek > 0 {
                Label("Diese Woche \(minutesThisWeek) Min. für \(subject.name) gelernt", systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            SectionTitle("Bis zur Arbeit")
        }
        .marginRow()
    }

    private func examCard(_ exam: Exam) -> some View {
        let readiness = LearningStore.readiness(for: exam, context: context)
        let sitting = readiness.topics.filter { $0.score >= 0.7 }.count
        let examSessions = sessions.filter { $0.examUID == exam.uid }
        let done = examSessions.filter { $0.status == .done }.count
        let days = Calendar.school.dateComponents([.day], from: Calendar.school.startOfDay(for: .now),
                                                  to: Calendar.school.startOfDay(for: exam.date)).day ?? 0
        let nextSession = examSessions.filter { $0.status == .planned && $0.date >= .now }.min { $0.date < $1.date }

        return HStack(spacing: 16) {
            ReadinessRing(value: readiness.overall, size: 58, lineWidth: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(exam.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(days == 0 ? "Heute" : days == 1 ? "Morgen" : "In \(days) Tagen · \(Fmt.dayMonth(exam.date))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(days <= 3 ? Palette.marginRed : Palette.secondaryInk)
                HStack(spacing: 12) {
                    if !readiness.topics.isEmpty {
                        Label("\(sitting)/\(readiness.topics.count) Themen sitzen", systemImage: "checkmark.seal")
                    }
                    if !examSessions.isEmpty {
                        Label("\(done)/\(examSessions.count) Einheiten", systemImage: "list.bullet.clipboard")
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                if let nextSession {
                    Text("Nächste Lerneinheit: \(Fmt.relativeDay(nextSession.date))")
                        .font(.caption)
                        .foregroundStyle(Palette.faintInk)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Pinboard

/// A cork board per subject: notes, videos, links, photos and sticky notes.
struct PinboardSection: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \PinItem.sortIndex) private var allPins: [PinItem]
    @Query(sort: \NoteDocument.updatedAt, order: .reverse) private var allNotes: [NoteDocument]
    let subject: SchoolSubject
    var openNote: (NoteDocument) -> Void

    @State private var editing: PinItem?
    @State private var askingLink = false
    @State private var linkText = ""
    @State private var camera = false
    @State private var library = false
    @State private var photoItem: PhotosPickerItem?
    @State private var viewing: PinItem?

    private var pins: [PinItem] { allPins.filter { $0.subjectUID == subject.uid } }
    private var subjectNotes: [NoteDocument] { allNotes.filter { $0.subjectUID == subject.uid } }

    var body: some View {
        Section {
            if pins.isEmpty {
                Text("Pinne Videos, Links, Fotos von der Tafel, Notizen oder Zettel an – alles für \(subject.name) an einem Ort.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(pins) { pin in
                        PinCard(pin: pin, note: pin.noteUID.flatMap { id in allNotes.first { $0.uid == id } })
                            .onTapGesture { open(pin) }
                            .contextMenu { menu(for: pin) }
                    }
                }
                .padding(.vertical, 10)
            }
            addMenu
        } header: {
            SectionTitle("Pinnwand")
        }
        .marginRow()
        .sheet(item: $editing) { pin in
            NavigationStack { PinEditor(pin: pin) }
                .tint(Palette.marginRed)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $viewing) { pin in
            PinPhotoViewer(pin: pin)
        }
        .alert("Video oder Link anheften", isPresented: $askingLink) {
            TextField("https://…", text: $linkText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("Anheften") { Task { await addLink(linkText) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("YouTube, Erklärvideos, Webseiten, Quizlet …")
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                camera = false
                addPhoto(image)
            } onCancel: {
                camera = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $library, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    addPhoto(image)
                }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                let pin = insert(.sticky)
                editing = pin
            } label: {
                Label("Zettel", systemImage: PinKind.sticky.symbol)
            }
            Button {
                linkText = UIPasteboard.general.hasURLs ? (UIPasteboard.general.url?.absoluteString ?? "") : ""
                askingLink = true
            } label: {
                Label("Video oder Link", systemImage: PinKind.video.symbol)
            }
            Button {
                camera = true
            } label: {
                Label("Foto aufnehmen", systemImage: "camera")
            }
            Button {
                library = true
            } label: {
                Label("Foto auswählen", systemImage: PinKind.photo.symbol)
            }
            Menu {
                Button {
                    let note = NoteDocument(title: "")
                    note.subjectUID = subject.uid
                    context.insert(note)
                    let pin = insert(.note)
                    pin.noteUID = note.uid
                    try? context.save()
                    openNote(note)
                } label: {
                    Label("Neue Notiz", systemImage: "square.and.pencil")
                }
                ForEach(subjectNotes.prefix(15)) { note in
                    Button(note.title.isEmpty ? "Ohne Titel" : note.title) {
                        let pin = insert(.note)
                        pin.noteUID = note.uid
                        try? context.save()
                    }
                }
            } label: {
                Label("Notiz", systemImage: PinKind.note.symbol)
            }
        } label: {
            Label("Anheften", systemImage: "pin")
        }
    }

    @ViewBuilder
    private func menu(for pin: PinItem) -> some View {
        if pin.kind != .note {
            Button {
                editing = pin
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
        }
        Menu {
            ForEach(SubjectColor.allCases) { color in
                Button(color.name) {
                    pin.colorKey = color.rawValue
                    try? context.save()
                }
            }
        } label: {
            Label("Farbe", systemImage: "paintpalette")
        }
        Button {
            move(pin, by: -1)
        } label: {
            Label("Nach vorne", systemImage: "arrow.up.left")
        }
        if let url = pin.url, pin.kind == .video || pin.kind == .link {
            ShareLink(item: url) { Label("Teilen", systemImage: "square.and.arrow.up") }
        }
        Button(role: .destructive) {
            context.delete(pin)
            try? context.save()
        } label: {
            Label("Lösen", systemImage: "pin.slash")
        }
    }

    // MARK: Actions

    @discardableResult
    private func insert(_ kind: PinKind) -> PinItem {
        let pin = PinItem(subjectUID: subject.uid, kind: kind)
        pin.sortIndex = (pins.map(\.sortIndex).max() ?? -1) + 1
        pin.colorKey = kind == .sticky ? ["mustard", "green", "blue", "coral"][pins.count % 4] : subject.colorKey
        context.insert(pin)
        try? context.save()
        Haptics.tap()
        return pin
    }

    private func open(_ pin: PinItem) {
        switch pin.kind {
        case .note:
            if let note = allNotes.first(where: { $0.uid == pin.noteUID }) { openNote(note) }
        case .video, .link:
            if let url = pin.url { openURL(url) }
        case .photo:
            viewing = pin
        case .sticky:
            editing = pin
        }
    }

    private func move(_ pin: PinItem, by offset: Int) {
        var ordered = pins
        guard let index = ordered.firstIndex(of: pin) else { return }
        let target = max(0, min(ordered.count - 1, index + offset))
        ordered.move(fromOffsets: IndexSet(integer: index), toOffset: target > index ? target + 1 : target)
        for (position, item) in ordered.enumerated() { item.sortIndex = position }
        try? context.save()
    }

    private func addLink(_ raw: String) async {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return }
        let isVideo = PinLinks.youTubeID(url) != nil || PinLinks.isVideoHost(url)
        let pin = insert(isVideo ? .video : .link)
        pin.urlString = url.absoluteString
        pin.title = url.host()?.replacingOccurrences(of: "www.", with: "") ?? "Link"
        try? context.save()
        if let title = await PinLinks.title(for: url) {
            pin.title = title
            try? context.save()
        }
    }

    private func addPhoto(_ image: UIImage) {
        guard let data = image.jpegForStorage(maxPixels: 1800),
              let stored = try? AttachmentStore.store(data, fileName: "pin.jpg") else { return }
        let pin = insert(.photo)
        pin.storedName = stored.storedName
        try? context.save()
    }
}

/// One card on the board, slightly turned like paper pinned to cork.
private struct PinCard: View {
    let pin: PinItem
    let note: NoteDocument?

    private var color: Color { (SubjectColor(rawValue: pin.colorKey) ?? .mustard).color }
    private var tilt: Double {
        let hash = pin.uid.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(hash % 7) - 3
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            .overlay(alignment: .top) {
                Circle()
                    .fill(Palette.marginRed)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .offset(y: -5)
            }
            .rotationEffect(.degrees(tilt))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pin.kind.title): \(label)")
    }

    private var label: String {
        switch pin.kind {
        case .note: note.map { $0.title.isEmpty ? "Ohne Titel" : $0.title } ?? "Gelöschte Notiz"
        case .sticky: pin.text.isEmpty ? "Leerer Zettel" : pin.text
        default: pin.title
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pin.kind {
        case .sticky:
            Text(pin.text.isEmpty ? "Tippen zum Schreiben" : pin.text)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(pin.text.isEmpty ? Palette.faintInk : Color.black.opacity(0.8))
                .padding(12)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(color.opacity(0.35))
                .background(Color.white)
        case .photo:
            if let image = UIImage(contentsOfFile: AttachmentStore.directory.appendingPathComponent(pin.storedName).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 130)
                    .clipped()
                    .overlay(alignment: .bottomLeading) { caption }
            } else {
                missing
            }
        case .video:
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.85))
                    if let id = pin.url.flatMap(PinLinks.youTubeID) {
                        AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.black.opacity(0.85)
                        }
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .frame(height: 86)
                .clipped()
                titleBlock
            }
            .background(Palette.sheet)
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link")
                    .font(.title3)
                    .foregroundStyle(color)
                titleBlock
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Palette.sheet)
        case .note:
            VStack(alignment: .leading, spacing: 0) {
                if let data = note?.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 86, alignment: .top)
                        .clipped()
                } else {
                    PaperInk.paper.frame(height: 86)
                }
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .padding(8)
            }
            .background(Palette.sheet)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pin.title.isEmpty ? (pin.url?.host() ?? "Link") : pin.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            if !pin.text.isEmpty {
                Text(pin.text)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var caption: some View {
        if !pin.title.isEmpty {
            Text(pin.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
    }

    private var missing: some View {
        Label("Fehlt", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Palette.sheet)
    }
}

/// Edit a sticky note, or the title and comment of a link, video or photo.
private struct PinEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var pin: PinItem

    var body: some View {
        Form {
            if pin.kind == .sticky {
                TextField("Was willst du dir merken?", text: $pin.text, axis: .vertical)
                    .font(.system(.body, design: .serif))
                    .lineLimit(4...12)
            } else {
                TextField("Titel", text: $pin.title)
                if pin.kind != .photo {
                    TextField("Adresse", text: $pin.urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                TextField("Kommentar, z. B. „ab 3:20 gut erklärt“", text: $pin.text, axis: .vertical)
            }
            Picker("Farbe", selection: $pin.colorKey) {
                ForEach(SubjectColor.allCases) { color in
                    Text(color.name).tag(color.rawValue)
                }
            }
        }
        .navigationTitle(pin.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

private struct PinPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let pin: PinItem

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(contentsOfFile: AttachmentStore.directory.appendingPathComponent(pin.storedName).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    ContentUnavailableView("Foto fehlt", systemImage: "photo")
                }
            }
            .navigationTitle(pin.title.isEmpty ? "Foto" : pin.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

/// Recognising videos and fetching titles for pinned links.
enum PinLinks {
    static func youTubeID(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        if host.hasSuffix("youtu.be") {
            return url.pathComponents.dropFirst().first
        }
        guard host.hasSuffix("youtube.com") else { return nil }
        if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return id
        }
        let parts = url.pathComponents
        if let index = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), index + 1 < parts.count {
            return parts[index + 1]
        }
        return nil
    }

    static func isVideoHost(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return ["vimeo.com", "tiktok.com", "simpleclub", "sofatutor", "dailymotion.com"].contains { host.contains($0) }
    }

    /// The page title (YouTube via oEmbed, otherwise the HTML <title>). Nil when offline.
    static func title(for url: URL) async -> String? {
        if youTubeID(url) != nil,
           var components = URLComponents(string: "https://www.youtube.com/oembed") {
            components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
            if let endpoint = components.url,
               let (data, _) = try? await URLSession.shared.data(from: endpoint),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = json["title"] as? String {
                return title
            }
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data.prefix(200_000), encoding: .utf8) ?? String(data: data.prefix(200_000), encoding: .isoLatin1) else {
            return nil
        }
        return htmlTitle(html)
    }

    static func htmlTitle(_ html: String) -> String? {
        guard let start = html.range(of: "<title", options: .caseInsensitive),
              let open = html.range(of: ">", range: start.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: .caseInsensitive, range: open.upperBound..<html.endIndex) else {
            return nil
        }
        let title = html[open.upperBound..<close.lowerBound]
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(120))
    }
}
