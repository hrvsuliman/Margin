import SwiftData
import SwiftUI

struct SubjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @State private var sheet: EditorSheet?
    @State private var pendingDelete: SchoolSubject?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TimetableView()
                    } label: {
                        Label("Stundenplan", systemImage: "tablecells")
                            .foregroundStyle(Palette.ink)
                    }
                    NavigationLink {
                        GradesView()
                    } label: {
                        Label("Noten", systemImage: "chart.bar.doc.horizontal")
                            .foregroundStyle(Palette.ink)
                    }
                }
                .marginRow()

                if subjects.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "books.vertical",
                            title: "Noch keine Fächer",
                            message: "Wähle deine Fächer aus einer Liste oder lege eigene an.",
                            actionTitle: "Fächer auswählen",
                            action: { sheet = .subjectTemplates }
                        )
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(subjects) { subject in
                            NavigationLink(value: subject) {
                                SubjectRow(subject: subject)
                            }
                            .marginRow()
                        }
                        .onMove(perform: move)
                        .onDelete { offsets in
                            pendingDelete = offsets.first.map { subjects[$0] }
                        }
                    } header: {
                        SectionTitle("Fächer", trailing: "\(subjects.count)")
                    }
                }
            }
            .marginList()
            .navigationTitle("Fächer")
            .navigationDestination(for: SchoolSubject.self) { subject in
                SubjectDetailView(subject: subject)
            }
            .navigationDestination(for: SchoolTask.self) { task in
                TaskDetailView(task: task)
            }
            .toolbar {
                if !subjects.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            sheet = .newSubject
                        } label: {
                            Label("Neues Fach", systemImage: "plus")
                        }
                        Button {
                            sheet = .subjectTemplates
                        } label: {
                            Label("Aus Liste auswählen", systemImage: "list.bullet")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Fach hinzufügen")
                }
            }
            .editorSheet($sheet)
            .confirmationDialog(
                "„\(pendingDelete?.name ?? "")“ löschen?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { subject in
                Button("Fach löschen", role: .destructive) {
                    SubjectActions.delete(subject, context: context)
                    pendingDelete = nil
                }
            } message: { _ in
                Text(SubjectActions.deleteMessage)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = subjects
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, subject) in ordered.enumerated() {
            subject.sortIndex = index
        }
        context.commit()
    }
}

struct SubjectRow: View {
    let subject: SchoolSubject

    private var subtitle: String {
        var parts: [String] = []
        if !subject.teacher.isEmpty { parts.append(subject.teacher) }
        let lessons = subject.lessons?.count ?? 0
        if lessons > 0 { parts.append("\(lessons) Std./Woche") }
        let open = (subject.tasks ?? []).filter { !$0.isDone }.count
        if open > 0 { parts.append("\(open) offen") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            SubjectDot(color: subject.color.color, size: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

enum SubjectActions {
    static let deleteMessage = "Stunden, Themen und Materialien des Fachs werden gelöscht. Aufgaben, Prüfungen und Termine bleiben erhalten."

    @MainActor
    static func delete(_ subject: SchoolSubject, context: ModelContext) {
        for attachment in subject.attachments ?? [] {
            AttachmentStore.delete(attachment, context: context)
        }
        context.delete(subject)
        context.commit()
    }
}
