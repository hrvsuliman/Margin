import PhotosUI
import SwiftData
import SwiftUI

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SchoolTask.createdAt, order: .reverse) private var tasks: [SchoolTask]
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]

    @State private var filter: Filter = .open
    @State private var subjectFilter: SchoolSubject?
    @State private var sheet: EditorSheet?
    @State private var pendingDelete: SchoolTask?
    @State private var scanCamera = false
    @State private var scanLibrary = false
    @State private var scanItem: PhotosPickerItem?
    @State private var scanning = false
    @State private var suggestion: HomeworkSuggestion?
    @Binding var plannerMode: String

    enum Filter: String, CaseIterable, Identifiable {
        case open, overdue, done
        var id: String { rawValue }
    }

    private var scoped: [SchoolTask] {
        guard let subjectFilter else { return tasks }
        return tasks.filter { $0.subject == subjectFilter }
    }

    private var openTasks: [SchoolTask] { scoped.filter { !$0.isDone } }
    private var overdueTasks: [SchoolTask] { openTasks.filter { $0.isOverdue() } }
    private var doneTasks: [SchoolTask] {
        scoped.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        Text("Offen \(openTasks.count)").tag(Filter.open)
                        Text("Überfällig \(overdueTasks.count)").tag(Filter.overdue)
                        Text("Erledigt").tag(Filter.done)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                content
            }
            .marginList()
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: filter)
            .navigationTitle("Aufgaben")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SchoolTask.self) { task in
                TaskDetailView(task: task)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    subjectMenu
                }
                ToolbarItem(placement: .principal) {
                    PlannerSwitch(mode: $plannerMode)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            sheet = .newTask(subject: subjectFilter, dueDate: nil, exam: nil, topic: nil)
                        } label: {
                            Label("Neue Aufgabe", systemImage: "plus")
                        }
                        Button {
                            scanCamera = true
                        } label: {
                            Label("Hausaufgabe fotografieren", systemImage: "camera")
                        }
                        Button {
                            scanLibrary = true
                        } label: {
                            Label("Aus Foto erkennen", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        sheet = .newTask(subject: subjectFilter, dueDate: nil, exam: nil, topic: nil)
                    }
                    .accessibilityLabel("Neue Aufgabe")
                }
            }
            .editorSheet($sheet)
            .fullScreenCover(isPresented: $scanCamera) {
                CameraPicker { image in
                    scanCamera = false
                    Task { await scan(image) }
                } onCancel: {
                    scanCamera = false
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $scanLibrary, selection: $scanItem, matching: .images)
            .onChange(of: scanItem) {
                guard let item = scanItem else { return }
                scanItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await scan(image)
                    }
                }
            }
            .sheet(item: $suggestion) { suggestion in
                NavigationStack {
                    TaskEditor(suggestion: suggestion,
                               subject: subjects.first { $0.name == suggestion.subjectName } ?? subjectFilter)
                }
                .tint(Palette.marginRed)
            }
            .overlay {
                if scanning {
                    ProgressView("Hausaufgabe wird gelesen …")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .confirmationDialog("Aufgabe löschen?", isPresented: deleteBinding, titleVisibility: .visible,
                                presenting: pendingDelete) { task in
                Button("Löschen", role: .destructive) { delete(task) }
            } message: { _ in
                Text("Teilaufgaben und Anhänge werden ebenfalls gelöscht.")
            }
        }
    }

    /// Reads the photo on the device and opens a pre-filled task (with the photo attached).
    private func scan(_ image: UIImage) async {
        scanning = true
        defer { scanning = false }
        let text = (try? await TextImport.text(from: image)) ?? ""
        var result = HomeworkParser.suggest(from: text, subjects: subjects.map(\.name))
        if result.title.isEmpty { result.title = "Hausaufgabe vom Foto" }
        result.photo = image.jpegForStorage()
        suggestion = result
    }

    @ViewBuilder
    private var content: some View {
        switch filter {
        case .open:
            if openTasks.isEmpty {
                emptyState(title: "Alles erledigt", message: "Keine offenen Aufgaben. Neue Aufgaben legst du mit + an.")
            } else {
                ForEach(groups(openTasks), id: \.title) { group in
                    Section {
                        rows(group.tasks)
                    } header: {
                        Text(group.title)
                    }
                }
            }
        case .overdue:
            if overdueTasks.isEmpty {
                emptyState(title: "Nichts überfällig", message: "Alle Aufgaben mit Datum liegen noch im Zeitplan.")
            } else {
                Section { rows(overdueTasks.sorted(by: Self.byDue)) }
            }
        case .done:
            if doneTasks.isEmpty {
                emptyState(title: "Noch nichts erledigt", message: "Erledigte Aufgaben erscheinen hier.")
            } else {
                Section { rows(doneTasks) }
            }
        }
    }

    private func rows(_ list: [SchoolTask]) -> some View {
        ForEach(list) { task in
            NavigationLink(value: task) {
                TaskRow(task: task, showSubject: subjectFilter == nil)
            }
            .swipeActions(edge: .leading) {
                Button {
                    TaskActions.toggleDone(task, context: context)
                } label: {
                    Label(task.isDone ? "Öffnen" : "Erledigt", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(SubjectColor.green.color)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    pendingDelete = task
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .marginRow()
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        Section {
            EmptyStateView(symbol: "checklist", title: title, message: message)
        }
        .listRowBackground(Color.clear)
    }

    private var subjectMenu: some View {
        Menu {
            Picker("Fach", selection: $subjectFilter) {
                Text("Alle Fächer").tag(nil as SchoolSubject?)
                ForEach(subjects) { subject in
                    Text(subject.name).tag(subject as SchoolSubject?)
                }
            }
        } label: {
            Label(subjectFilter?.name ?? "Alle Fächer",
                  systemImage: subjectFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func delete(_ task: SchoolTask) {
        for attachment in task.attachments ?? [] {
            AttachmentStore.delete(attachment, context: context)
        }
        context.delete(task)
        context.commit()
        pendingDelete = nil
    }

    // MARK: Grouping

    struct DueGroup {
        let title: String
        let tasks: [SchoolTask]
    }

    static func byDue(_ a: SchoolTask, _ b: SchoolTask) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): x == y ? a.priorityRaw > b.priorityRaw : x < y
        case (nil, _?): false
        case (_?, nil): true
        case (nil, nil): a.createdAt > b.createdAt
        }
    }

    private func groups(_ list: [SchoolTask], now: Date = .now) -> [DueGroup] {
        let calendar = Calendar.school
        let endOfWeek = calendar.addingDays(7, to: calendar.startOfWeek(for: now))
        var buckets: [String: [SchoolTask]] = [:]
        let order = ["Überfällig", "Heute", "Morgen", "Diese Woche", "Später", "Ohne Datum"]

        for task in list {
            let key: String
            if task.isOverdue(now: now) {
                key = "Überfällig"
            } else if let due = task.dueDate {
                let days = calendar.daysBetween(now, due)
                if days <= 0 { key = "Heute" }
                else if days == 1 { key = "Morgen" }
                else if due < endOfWeek { key = "Diese Woche" }
                else { key = "Später" }
            } else {
                key = "Ohne Datum"
            }
            buckets[key, default: []].append(task)
        }
        return order.compactMap { key in
            guard let tasks = buckets[key] else { return nil }
            return DueGroup(title: key, tasks: tasks.sorted(by: Self.byDue))
        }
    }
}
