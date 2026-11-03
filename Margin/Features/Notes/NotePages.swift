import SwiftData
import SwiftUI

/// The structure around notes: subpages, pins, `[[links]]` and backlinks.
/// Stored in `NoteMeta`, keyed by the note's uid, so notes themselves stay unchanged.
@MainActor
enum NotePages {
    static func meta(for note: NoteDocument, in metas: [NoteMeta]) -> NoteMeta? {
        metas.first { $0.noteUID == note.uid }
    }

    static func ensureMeta(for note: NoteDocument, context: ModelContext) -> NoteMeta {
        let metas = (try? context.fetch(FetchDescriptor<NoteMeta>())) ?? []
        if let existing = meta(for: note, in: metas) { return existing }
        let meta = NoteMeta(noteUID: note.uid)
        context.insert(meta)
        return meta
    }

    static func children(of note: NoteDocument, notes: [NoteDocument], metas: [NoteMeta]) -> [NoteDocument] {
        let ids = Set(metas.filter { $0.parentUID == note.uid }.compactMap(\.noteUID))
        return notes.filter { ids.contains($0.uid) }.sorted { $0.createdAt < $1.createdAt }
    }

    static func parent(of note: NoteDocument, notes: [NoteDocument], metas: [NoteMeta]) -> NoteDocument? {
        guard let parentUID = meta(for: note, in: metas)?.parentUID else { return nil }
        return notes.first { $0.uid == parentUID }
    }

    private static func sameTitle(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces)
            .compare(b.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Notes this note links to with `[[Titel]]`.
    static func linked(from note: NoteDocument, notes: [NoteDocument]) -> [NoteDocument] {
        NoteBlock.links(in: note.body).compactMap { title in
            notes.first { $0.uid != note.uid && sameTitle($0.title, title) }
        }
    }

    /// Notes that link to this one.
    static func backlinks(to note: NoteDocument, notes: [NoteDocument]) -> [NoteDocument] {
        guard !note.title.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return notes.filter { other in
            other.uid != note.uid && NoteBlock.links(in: other.body).contains { sameTitle($0, note.title) }
        }
    }

    /// Titles linked with `[[…]]` that no note has yet.
    static func missingLinks(in note: NoteDocument, notes: [NoteDocument]) -> [String] {
        NoteBlock.links(in: note.body).filter { title in !notes.contains { sameTitle($0.title, title) } }
    }

    @discardableResult
    static func addSubpage(to parent: NoteDocument, title: String = "", context: ModelContext) -> NoteDocument {
        let child = NoteDocument(title: title)
        child.subjectUID = parent.subjectUID
        child.topicUID = parent.topicUID
        child.examUID = parent.examUID
        child.folder = parent.folder
        child.profileUID = parent.profileUID
        context.insert(child)
        let meta = NoteMeta(noteUID: child.uid)
        meta.parentUID = parent.uid
        context.insert(meta)
        try? context.save()
        return child
    }

    static func togglePin(_ note: NoteDocument, context: ModelContext) {
        let meta = ensureMeta(for: note, context: context)
        meta.pinned.toggle()
        try? context.save()
        Haptics.selection()
    }

    /// Deletes a note; its subpages move up one level.
    static func delete(_ note: NoteDocument, context: ModelContext) {
        let metas = (try? context.fetch(FetchDescriptor<NoteMeta>())) ?? []
        let own = meta(for: note, in: metas)
        for child in metas where child.parentUID == note.uid {
            child.parentUID = own?.parentUID
        }
        if let own { context.delete(own) }
        context.delete(note)
        try? context.save()
    }
}

/// Parent, subpages, links and backlinks of a note, as a row of chips above the text.
struct NotePagesBar: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteDocument.updatedAt, order: .reverse) private var notes: [NoteDocument]
    @Query private var metas: [NoteMeta]
    let document: NoteDocument

    @State private var opened: NoteDocument?

    var body: some View {
        let parent = NotePages.parent(of: document, notes: notes, metas: metas)
        let children = NotePages.children(of: document, notes: notes, metas: metas)
        let linked = NotePages.linked(from: document, notes: notes)
        let backlinks = NotePages.backlinks(to: document, notes: notes)
        let missing = NotePages.missingLinks(in: document, notes: notes)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let parent {
                    chip(parent, symbol: "arrow.up")
                }
                ForEach(children) { chip($0, symbol: "doc") }
                ForEach(linked) { chip($0, symbol: "link") }
                ForEach(missing, id: \.self) { title in
                    Button {
                        opened = NotePages.addSubpage(to: document, title: title, context: context)
                    } label: {
                        Label(title, systemImage: "plus")
                            .lineLimit(1)
                    }
                    .buttonStyle(ChipStyle(dashed: true))
                    .accessibilityHint("Legt die verlinkte Seite an")
                }
                if !backlinks.isEmpty {
                    Menu {
                        ForEach(backlinks) { note in
                            Button(note.title.isEmpty ? "Ohne Titel" : note.title) { opened = note }
                        }
                    } label: {
                        Label("Erwähnt in \(backlinks.count)", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(ChipStyle())
                }
                Button {
                    opened = NotePages.addSubpage(to: document, context: context)
                } label: {
                    Label("Unterseite", systemImage: "plus")
                }
                .buttonStyle(ChipStyle(dashed: true))
            }
            .font(.footnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .navigationDestination(item: $opened) { note in
            NoteEditorView(document: note)
        }
    }

    private func chip(_ note: NoteDocument, symbol: String) -> some View {
        Button {
            opened = note
        } label: {
            Label(note.title.isEmpty ? "Ohne Titel" : note.title, systemImage: symbol)
                .lineLimit(1)
        }
        .buttonStyle(ChipStyle())
    }
}

private struct ChipStyle: ButtonStyle {
    var dashed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(dashed ? Palette.secondaryInk : Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if dashed {
                    Capsule().strokeBorder(Palette.ruling, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else {
                    Capsule().fill(Palette.sheet)
                }
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Ready-made page structures, like Notion templates, for school.
enum NoteTemplate: String, CaseIterable, Identifiable {
    case lesson, cornell, vocabulary, experiment, summary, presentation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lesson: "Stundenmitschrift"
        case .cornell: "Cornell-Notiz"
        case .vocabulary: "Vokabeln"
        case .experiment: "Versuchsprotokoll"
        case .summary: "Lernzettel"
        case .presentation: "Referat"
        }
    }

    var symbol: String {
        switch self {
        case .lesson: "pencil.and.list.clipboard"
        case .cornell: "rectangle.split.2x1"
        case .vocabulary: "character.book.closed"
        case .experiment: "flask"
        case .summary: "list.bullet.rectangle"
        case .presentation: "person.wave.2"
        }
    }

    var body: String {
        switch self {
        case .lesson:
            """
            ## Thema
            Worum geht es heute?

            ## Mitschrift
            -

            ## Hausaufgabe
            - [ ] Aufgabe eintragen
            """
        case .cornell:
            """
            ## Fragen
            - Was ist …?
            - Warum …?

            ## Notizen
            Hier mitschreiben.

            ---
            ## Zusammenfassung
            > In zwei, drei Sätzen: Worum ging es?
            """
        case .vocabulary:
            """
            ## Vokabeln
            Jede Zeile mit „::“ wird automatisch eine Karteikarte.

            the house :: das Haus
            to learn :: lernen
            """
        case .experiment:
            """
            ## Fragestellung
            Was wollen wir herausfinden?

            ## Vermutung
            > Ich vermute, dass …

            ## Material
            -

            ## Durchführung
            Schritt für Schritt.

            ## Beobachtung
            | Zeit | Messwert |
            |---|---|
            | 0 min | |

            ## Auswertung
            Ergebnis und Erklärung.
            """
        case .summary:
            """
            ## Das Wichtigste
            > Der eine Satz, den ich mir merken muss.

            ## Begriffe
            Begriff :: Erklärung

            ## Kann ich das?
            - [ ] Ich kann es erklären
            - [ ] Ich kann eine Aufgabe dazu lösen
            """
        case .presentation:
            """
            ## Gliederung
            1. Einleitung
            2. Hauptteil
            3. Fazit

            ## Quellen
            -

            ## Bis zum Vortrag
            - [ ] Recherche
            - [ ] Folien
            - [ ] Probe halten
            """
        }
    }
}
