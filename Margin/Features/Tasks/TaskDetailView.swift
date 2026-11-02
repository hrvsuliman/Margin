import SwiftData
import SwiftUI

/// A task at a glance: tick off subtasks, add attachments, change status.
struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: SchoolTask
    /// True when shown as a sheet (adds a "Fertig" button).
    var showsDoneButton = false

    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))

            Section {
                Button {
                    TaskActions.toggleDone(task, context: context)
                } label: {
                    Label(task.isDone ? "Wieder öffnen" : "Als erledigt markieren",
                          systemImage: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        .font(.body.weight(.semibold))
                }
                Picker("Status", selection: $task.status) {
                    ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                }
            }
            .marginRow()

            Section {
                if let due = task.dueDate {
                    LabeledContent("Fällig") {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(task.hasDueTime ? "\(Fmt.shortDay(due)), \(Fmt.time(due))" : Fmt.longDay(due))
                            Text(task.isOverdue() ? "überfällig" : Fmt.relativeDay(due))
                                .font(.caption)
                                .foregroundStyle(task.isOverdue() ? Palette.marginRed : Palette.secondaryInk)
                        }
                    }
                } else {
                    LabeledContent("Fällig", value: "Kein Datum")
                }
                LabeledContent("Priorität", value: task.priority.title)
                if task.estimatedMinutes > 0 {
                    LabeledContent("Geschätzte Zeit", value: Fmt.duration(minutes: task.estimatedMinutes))
                }
                if let reminder = task.reminderDate {
                    LabeledContent("Erinnerung", value: "\(Fmt.shortDay(reminder)), \(Fmt.time(reminder))")
                }
                if let topic = task.topic {
                    LabeledContent("Thema", value: topic.title)
                }
                if let exam = task.exam {
                    LabeledContent("Prüfung", value: "\(exam.displayTitle) · \(Fmt.dayMonth(exam.date))")
                }
            }
            .marginRow()

            if !task.details.isEmpty {
                Section("Notizen") {
                    Text(task.details)
                        .textSelection(.enabled)
                }
                .marginRow()
            }

            let subtasks = task.sortedSubtasks
            if !subtasks.isEmpty {
                Section {
                    ForEach(subtasks) { subtask in
                        HStack {
                            CheckButton(isOn: subtask.isDone, color: task.subject?.color.color ?? Palette.ink) {
                                subtask.isDone.toggle()
                                Haptics.selection()
                                context.commit()
                            }
                            Text(subtask.title)
                                .foregroundStyle(subtask.isDone ? Palette.secondaryInk : Palette.ink)
                                .strikethrough(subtask.isDone, color: Palette.secondaryInk)
                        }
                    }
                } header: {
                    HStack {
                        Text("Teilaufgaben")
                        Spacer()
                        Text("\(subtasks.filter(\.isDone).count) von \(subtasks.count)")
                    }
                }
                .marginRow()
            }

            AttachmentsSection(owner: .task(task))
                .marginRow()

            Section {
                Button("Aufgabe löschen", role: .destructive) { confirmDelete = true }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(task.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { TaskEditor(task: task) }
                .tint(Palette.marginRed)
        }
        .onChange(of: task.statusRaw) {
            context.commit()
        }
        .confirmationDialog("Aufgabe löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: delete)
        } message: {
            Text("Teilaufgaben und Anhänge werden ebenfalls gelöscht.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            MarginBar(color: task.subject?.color.color ?? Palette.marginRed, width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(task.isDone ? Palette.secondaryInk : Palette.ink)
                    .strikethrough(task.isDone, color: Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let subject = task.subject {
                        SubjectDot(color: subject.color.color, size: 8)
                        Text(subject.name)
                        Text("·")
                    }
                    Label(task.kind.title, systemImage: task.kind.symbol)
                }
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private func delete() {
        let task = task
        let context = context
        dismiss()
        Deferred.afterDismiss {
            for attachment in task.attachments ?? [] {
                AttachmentStore.delete(attachment, context: context)
            }
            context.delete(task)
            context.commit()
        }
    }
}
