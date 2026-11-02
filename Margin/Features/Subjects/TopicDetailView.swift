import SwiftData
import SwiftUI

/// A topic with its notes and subtopics. Edits are saved directly.
struct TopicDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var topic: Topic

    @State private var addingSubtopic = false
    @State private var newTitle = ""
    @State private var sheet: EditorSheet?

    var body: some View {
        List {
            Section {
                TextField("Titel", text: $topic.title, axis: .vertical)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                if let subject = topic.subject {
                    HStack(spacing: 6) {
                        SubjectDot(color: subject.color.color, size: 8)
                        Text(path(for: topic, subject: subject))
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                }
            }
            .marginRow()

            Section("Notizen") {
                TextField("Definitionen, Formeln, offene Fragen …", text: $topic.details, axis: .vertical)
                    .lineLimit(4...30)
            }
            .marginRow()

            Section {
                ForEach(topic.sortedChildren) { child in
                    NavigationLink {
                        TopicDetailView(topic: child)
                    } label: {
                        TopicRow(topic: child)
                    }
                }
                .onMove { source, destination in
                    var ordered = topic.sortedChildren
                    ordered.move(fromOffsets: source, toOffset: destination)
                    for (index, child) in ordered.enumerated() { child.sortIndex = index }
                    context.commit()
                }
                .onDelete { offsets in
                    let children = topic.sortedChildren
                    for index in offsets { context.delete(children[index]) }
                    context.commit()
                }
                Button {
                    addingSubtopic = true
                } label: {
                    Label("Unterthema hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Unterthemen")
            }
            .marginRow()

            Section {
                ForEach((topic.tasks ?? []).sorted(by: TasksView.byDue)) { task in
                    NavigationLink(value: task) {
                        TaskRow(task: task, showSubject: false)
                    }
                }
                Button {
                    sheet = .newTask(subject: topic.subject, dueDate: nil, exam: nil, topic: topic)
                } label: {
                    Label("Aufgabe zu diesem Thema", systemImage: "plus")
                }
            } header: {
                Text("Aufgaben")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Thema")
        .navigationBarTitleDisplayMode(.inline)
        .editorSheet($sheet)
        .alert("Neues Unterthema", isPresented: $addingSubtopic) {
            TextField("Titel", text: $newTitle)
            Button("Hinzufügen", action: addSubtopic)
            Button("Abbrechen", role: .cancel) { newTitle = "" }
        }
        .onDisappear {
            if topic.modelContext != nil { context.commit() }
        }
    }

    /// "Mathematik › Analysis"
    private func path(for topic: Topic, subject: SchoolSubject) -> String {
        var names: [String] = []
        var current = topic.parent
        while let parent = current {
            names.insert(parent.title, at: 0)
            current = parent.parent
        }
        return ([subject.name] + names).joined(separator: " › ")
    }

    private func addSubtopic() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        newTitle = ""
        guard !title.isEmpty else { return }
        let child = Topic(title: title, subject: nil, sortIndex: topic.children?.count ?? 0)
        context.insert(child)
        child.subject = topic.subject
        child.parent = topic
        context.commit()
    }
}
