import SwiftData
import SwiftUI

/// "Nachbereiten": summary, key points, to-dos and flashcards from a note or lesson transcript.
/// Nothing is changed until the user taps "Übernehmen".
struct SummaryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    let document: NoteDocument

    @State private var engine: NoteSummarizer.Engine?
    @State private var result = ""
    @State private var todos: [String] = []
    @State private var selected = Set<String>()
    @State private var working = false
    @State private var error: String?

    private var subject: SchoolSubject? { subjects.first { $0.uid == document.subjectUID } }

    var body: some View {
        NavigationStack {
            Form {
                if result.isEmpty {
                    chooser
                } else {
                    Section {
                        TextEditor(text: $result)
                            .font(.callout)
                            .frame(minHeight: 260)
                    } header: {
                        Text("Ergebnis – du kannst es noch ändern")
                    } footer: {
                        Text("Wird unten an die Notiz angehängt. Zeilen „Begriff :: Erklärung“ werden zu Karteikarten.")
                    }
                    .marginRow()
                    if !todos.isEmpty {
                        Section("Als Aufgaben anlegen") {
                            ForEach(todos, id: \.self) { todo in
                                Toggle(todo, isOn: Binding(
                                    get: { selected.contains(todo) },
                                    set: { if $0 { selected.insert(todo) } else { selected.remove(todo) } }
                                ))
                            }
                        }
                        .marginRow()
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(Palette.marginRed)
                    }
                    .marginRow()
                }
            }
            .marginList()
            .navigationTitle("Nachbereiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if !result.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Übernehmen", action: apply)
                    }
                }
            }
            .overlay {
                if working {
                    ProgressView("Wird zusammengefasst …")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .tint(Palette.marginRed)
        .onAppear { engine = NoteSummarizer.availableEngines.first }
    }

    @ViewBuilder
    private var chooser: some View {
        let engines = NoteSummarizer.availableEngines
        Section {
            Label("Kurze Zusammenfassung, die wichtigsten Punkte, genannte Hausaufgaben als To-dos und Karteikarten zu den Fachbegriffen.",
                  systemImage: "wand.and.stars")
                .font(.callout)
            if engines.isEmpty {
                Text(NoteSummarizer.Failure.noEngine.localizedDescription)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                Picker("Mit", selection: $engine) {
                    ForEach(engines) { Text($0.title).tag($0 as NoteSummarizer.Engine?) }
                }
                if let engine {
                    Text(engine.privacy)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Button {
                    Task { await run() }
                } label: {
                    Label("Nachbereiten", systemImage: "sparkles")
                }
                .disabled(engine == nil || working)
            }
        }
        .marginRow()
    }

    private func run() async {
        guard let engine else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            let text = document.body
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(NoteBlock.imagePrefix) }
                .joined(separator: "\n")
            result = try await NoteSummarizer.summarize(text, title: document.title, subject: subject?.name, engine: engine)
            todos = NoteSummarizer.todos(in: result)
            selected = Set(todos)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply() {
        document.body += (document.body.hasSuffix("\n") ? "\n" : "\n\n") + "---\n" + result
        document.updatedAt = .now
        for todo in todos where selected.contains(todo) {
            let task = SchoolTask(title: HomeworkParser.cleanTitle(todo), kind: .homework)
            context.insert(task)
            task.subject = subject
            task.dueDate = HomeworkParser.dueDate(in: todo, today: .now, calendar: .school)
        }
        context.commit()
        LearningStore.syncCards(for: document, context: context)
        Haptics.success()
        dismiss()
    }
}
