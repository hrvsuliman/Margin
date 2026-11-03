import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A file that arrived through "Teilen → Margin" or by opening a .margin file.
struct IncomingFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Decide what to do with a shared file: import a classmate's deck or note,
/// turn a document into a note, attach it to a subject, or ask the tutor.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    let file: IncomingFile
    var openNote: (NoteDocument) -> Void

    @State private var shared: ShareFile?
    @State private var message: String?
    @State private var working = false
    @State private var subjectUID: UUID?

    private var name: String { file.url.lastPathComponent }
    private var type: UTType { UTType(filenameExtension: file.url.pathExtension) ?? .data }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(name, systemImage: shared != nil ? "square.and.arrow.down" : "doc")
                        .font(.headline)
                    if let shared {
                        Text(shared.kind == "deck"
                             ? "\(shared.cards?.count ?? 0) Karteikarten\(shared.subject.map { " · \($0)" } ?? "")"
                             : "Notiz\(shared.subject.map { " · \($0)" } ?? "")")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .marginRow()

                if let shared {
                    Section {
                        Button {
                            message = ShareService.importFile(shared, context: context)
                            Haptics.success()
                        } label: {
                            Label("Importieren", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(message != nil)
                    } footer: {
                        Text("Von jemandem geteilt. Karten landen bei deinen Karteikarten, Notizen in deiner Handschrift bei den Notizen.")
                    }
                    .marginRow()
                } else {
                    Section {
                        Button {
                            Task { await makeNote() }
                        } label: {
                            Label("Text in neue Notiz übernehmen", systemImage: "doc.text")
                        }
                        Picker("Fach", selection: $subjectUID) {
                            Text("Fach wählen").tag(nil as UUID?)
                            ForEach(subjects) { Text($0.name).tag($0.uid as UUID?) }
                        }
                        Button {
                            attach()
                        } label: {
                            Label("Als Material zum Fach legen", systemImage: "paperclip")
                        }
                        .disabled(subjectUID == nil)
                    } footer: {
                        Text("Texterkennung läuft auf dem iPhone, auch bei Fotos und gescannten PDFs.")
                    }
                    .marginRow()
                }

                if let message {
                    Section {
                        Label(message, systemImage: "checkmark.circle")
                            .foregroundStyle(SubjectColor.green.color)
                    }
                    .marginRow()
                }
            }
            .marginList()
            .navigationTitle("Geteilt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .overlay {
                if working { ProgressView("Wird gelesen …").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
        }
        .tint(Palette.marginRed)
        .onAppear(perform: load)
    }

    private func load() {
        guard file.url.pathExtension.lowercased() == "margin" else { return }
        let scoped = file.url.startAccessingSecurityScopedResource()
        defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: file.url) {
            shared = ShareService.read(data)
            if shared == nil { message = "Diese Datei konnte nicht gelesen werden." }
        }
    }

    private func makeNote() async {
        working = true
        defer { working = false }
        do {
            let text = try await TextImport.text(from: file.url)
            let note = NoteDocument(title: (name as NSString).deletingPathExtension)
            note.body = text
            note.subjectUID = subjectUID
            context.insert(note)
            try? context.save()
            Haptics.success()
            dismiss()
            openNote(note)
        } catch {
            message = error.localizedDescription
        }
    }

    private func attach() {
        guard let subject = subjects.first(where: { $0.uid == subjectUID }) else { return }
        do {
            let attachment = try AttachmentStore.importFile(at: file.url)
            context.insert(attachment)
            attachment.subject = subject
            context.commit()
            message = "Bei \(subject.name) unter Materialien abgelegt."
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }
}
