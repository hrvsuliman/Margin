import SwiftData
import SwiftUI

/// Create or edit a task. Works on a draft copy, so "Abbrechen" really discards.
struct TaskEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query private var holidays: [Holiday]

    private let task: SchoolTask?
    @State private var draft: Draft
    @State private var newSubtaskTitle = ""
    @FocusState private var titleFocused: Bool

    struct SubtaskDraft: Identifiable {
        var id = UUID()
        var existing: Subtask?
        var title: String
        var isDone: Bool
    }

    struct Draft {
        var title = ""
        var details = ""
        var kind: TaskKind = .homework
        var priority: TaskPriority = .normal
        var status: TaskStatus = .open
        var subject: SchoolSubject?
        var topic: Topic?
        var exam: Exam?
        var hasDueDate = true
        var dueDate = Calendar.school.addingDays(1, to: Calendar.school.startOfDay(for: .now))
        var hasDueTime = false
        var hasReminder = false
        var reminderDate = Calendar.school.date(on: .now, minute: 17 * 60)
        var estimatedMinutes = 0
        var subtasks: [SubtaskDraft] = []
    }

    /// Edit an existing task.
    init(task: SchoolTask) {
        self.task = task
        var draft = Draft()
        draft.title = task.title
        draft.details = task.details
        draft.kind = task.kind
        draft.priority = task.priority
        draft.status = task.status
        draft.subject = task.subject
        draft.topic = task.topic
        draft.exam = task.exam
        draft.hasDueDate = task.dueDate != nil
        draft.dueDate = task.dueDate ?? draft.dueDate
        draft.hasDueTime = task.hasDueTime
        draft.hasReminder = task.reminderDate != nil
        draft.reminderDate = task.reminderDate ?? draft.reminderDate
        draft.estimatedMinutes = task.estimatedMinutes
        draft.subtasks = task.sortedSubtasks.map {
            SubtaskDraft(existing: $0, title: $0.title, isDone: $0.isDone)
        }
        _draft = State(initialValue: draft)
    }

    /// Create a new task, optionally pre-filled.
    init(subject: SchoolSubject? = nil, dueDate: Date? = nil, exam: Exam? = nil, topic: Topic? = nil) {
        self.task = nil
        var draft = Draft()
        draft.subject = subject ?? exam?.subject ?? topic?.subject
        draft.exam = exam
        draft.topic = topic
        if exam != nil { draft.kind = .examPrep }
        if let dueDate { draft.dueDate = Calendar.school.startOfDay(for: dueDate) }
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { task == nil }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("Titel, z. B. S. 42 Nr. 3", text: $draft.title, axis: .vertical)
                    .font(.body.weight(.medium))
                    .focused($titleFocused)
                Picker("Fach", selection: $draft.subject) {
                    Text("Kein Fach").tag(nil as SchoolSubject?)
                    ForEach(subjects) { subject in
                        Text(subject.name).tag(subject as SchoolSubject?)
                    }
                }
                Picker("Art", selection: $draft.kind) {
                    ForEach(TaskKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
            }
            .marginRow()

            Section("Fälligkeit") {
                Toggle("Fälligkeitsdatum", isOn: $draft.hasDueDate.animation())
                if draft.hasDueDate {
                    DatePicker(
                        "Fällig am",
                        selection: $draft.dueDate,
                        displayedComponents: draft.hasDueTime ? [.date, .hourAndMinute] : [.date]
                    )
                    Toggle("Mit Uhrzeit", isOn: $draft.hasDueTime)
                    if let subject = draft.subject,
                       let next = Timetable.nextLessonDay(for: subject, holidays: holidays) {
                        Button {
                            draft.dueDate = next
                            draft.hasDueTime = false
                            Haptics.selection()
                        } label: {
                            Label("Zur nächsten Stunde: \(Fmt.shortDay(next))", systemImage: "arrow.uturn.right")
                        }
                    }
                }
            }
            .marginRow()

            Section {
                Picker("Priorität", selection: $draft.priority) {
                    ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Geschätzte Zeit", selection: $draft.estimatedMinutes) {
                    Text("Keine Angabe").tag(0)
                    ForEach([10, 15, 20, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                        Text(Fmt.duration(minutes: minutes)).tag(minutes)
                    }
                }
                if !isNew {
                    Picker("Status", selection: $draft.status) {
                        ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .marginRow()

            Section {
                Toggle("Erinnerung", isOn: $draft.hasReminder.animation())
                if draft.hasReminder {
                    DatePicker("Um", selection: $draft.reminderDate)
                }
            } footer: {
                if !draft.hasReminder {
                    Text("Ohne eigene Erinnerung gilt die Standard-Erinnerung aus den Einstellungen.")
                }
            }
            .marginRow()

            Section("Teilaufgaben") {
                ForEach($draft.subtasks) { $subtask in
                    HStack {
                        CheckButton(isOn: subtask.isDone, color: Palette.ink) {
                            subtask.isDone.toggle()
                        }
                        TextField("Teilaufgabe", text: $subtask.title)
                    }
                }
                .onDelete { draft.subtasks.remove(atOffsets: $0) }
                .onMove { draft.subtasks.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    Image(systemName: "plus")
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: 30)
                    TextField("Teilaufgabe hinzufügen", text: $newSubtaskTitle)
                        .submitLabel(.next)
                        .onSubmit(addSubtask)
                }
            }
            .marginRow()

            if draft.subject != nil || !exams.isEmpty {
                Section("Zuordnung") {
                    if let subject = draft.subject, !(subject.topics ?? []).isEmpty {
                        Picker("Thema", selection: $draft.topic) {
                            Text("Kein Thema").tag(nil as Topic?)
                            ForEach(TopicOutline.flatten(subject.rootTopics), id: \.topic.uid) { entry in
                                Text(String(repeating: "   ", count: entry.depth) + entry.topic.title)
                                    .tag(entry.topic as Topic?)
                            }
                        }
                    }
                    Picker("Prüfung", selection: $draft.exam) {
                        Text("Keine Prüfung").tag(nil as Exam?)
                        ForEach(relevantExams) { exam in
                            Text("\(exam.displayTitle) · \(Fmt.dayMonth(exam.date))").tag(exam as Exam?)
                        }
                    }
                }
                .marginRow()
            }

            Section("Notizen") {
                TextField("Beschreibung, Hinweise, Links …", text: $draft.details, axis: .vertical)
                    .lineLimit(3...12)
            }
            .marginRow()

        }
        .marginList()
        .navigationTitle(isNew ? "Neue Aufgabe" : "Aufgabe bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save)
                    .disabled(!canSave)
            }
        }
        .onChange(of: draft.subject) {
            if let topic = draft.topic, topic.subject != draft.subject { draft.topic = nil }
        }
        .onAppear {
            if isNew { titleFocused = true }
        }
    }

    private var relevantExams: [Exam] {
        let today = Calendar.school.startOfDay(for: .now)
        return exams.filter { exam in
            (exam.date >= today || exam == draft.exam) && (draft.subject == nil || exam.subject == draft.subject)
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        draft.subtasks.append(SubtaskDraft(title: title, isDone: false))
        newSubtaskTitle = ""
    }

    private func save() {
        addSubtask()
        let target = task ?? SchoolTask(title: "")
        if task == nil { context.insert(target) }

        target.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.details = draft.details
        target.kind = draft.kind
        target.priority = draft.priority
        target.status = isNew ? .open : draft.status
        target.subject = draft.subject
        target.topic = draft.topic
        target.exam = draft.exam
        target.dueDate = draft.hasDueDate
            ? (draft.hasDueTime ? draft.dueDate : Calendar.school.startOfDay(for: draft.dueDate))
            : nil
        target.hasDueTime = draft.hasDueDate && draft.hasDueTime
        target.reminderDate = draft.hasReminder ? draft.reminderDate : nil
        target.estimatedMinutes = draft.estimatedMinutes

        // Sync subtasks: update kept ones, add new ones, delete removed ones.
        let kept = Set(draft.subtasks.compactMap { $0.existing?.uid })
        for old in target.subtasks ?? [] where !kept.contains(old.uid) {
            context.delete(old)
        }
        var index = 0
        for entry in draft.subtasks {
            let title = entry.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else {
                if let existing = entry.existing { context.delete(existing) }
                continue
            }
            if let existing = entry.existing {
                existing.title = title
                existing.isDone = entry.isDone
                existing.sortIndex = index
            } else {
                let subtask = Subtask(title: title, sortIndex: index, isDone: entry.isDone)
                context.insert(subtask)
                subtask.task = target
            }
            index += 1
        }

        context.commit()
        Haptics.success()
        dismiss()
    }
}

/// Flattens a topic tree for pickers, keeping the depth for indentation.
enum TopicOutline {
    struct Entry {
        let topic: Topic
        let depth: Int
    }

    static func flatten(_ topics: [Topic], depth: Int = 0) -> [Entry] {
        topics.flatMap { topic in
            [Entry(topic: topic, depth: depth)] + flatten(topic.sortedChildren, depth: depth + 1)
        }
    }
}
