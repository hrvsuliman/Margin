import SwiftData
import SwiftUI

/// Everything about one subject: timetable, exams, tasks, topics and materials.
struct SubjectDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var subject: SchoolSubject

    @State private var sheet: EditorSheet?
    @State private var addingTopic = false
    @State private var newTopicTitle = ""
    @State private var confirmDelete = false
    @State private var showPastExams = false

    private var today: Date { Calendar.school.startOfDay(for: .now) }
    private var upcomingExams: [Exam] {
        (subject.exams ?? []).filter { $0.date >= today }.sorted { $0.date < $1.date }
    }
    private var pastExams: [Exam] {
        (subject.exams ?? []).filter { $0.date < today }.sorted { $0.date > $1.date }
    }
    private var openTasks: [SchoolTask] {
        (subject.tasks ?? []).filter { !$0.isDone }.sorted(by: TasksView.byDue)
    }
    private var doneCount: Int { (subject.tasks ?? []).filter(\.isDone).count }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

            lessonsSection
            examsSection
            tasksSection
            topicsSection

            AttachmentsSection(owner: .subject(subject), title: "Materialien")
                .marginRow()

            if !subject.notes.isEmpty {
                Section("Notizen") {
                    Text(subject.notes).textSelection(.enabled)
                }
                .marginRow()
            }

            Section {
                Button("Fach löschen", role: .destructive) { confirmDelete = true }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") { sheet = .subject(subject) }
            }
        }
        .editorSheet($sheet)
        .alert("Neues Thema", isPresented: $addingTopic) {
            TextField("z. B. Ableitungen", text: $newTopicTitle)
            Button("Hinzufügen", action: addTopic)
            Button("Abbrechen", role: .cancel) { newTopicTitle = "" }
        }
        .confirmationDialog("„\(subject.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Fach löschen", role: .destructive, action: deleteSubject)
        } message: {
            Text(SubjectActions.deleteMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            MarginBar(color: subject.color.color, width: 5)
                .frame(height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                let info = [subject.teacher, subject.room.isEmpty ? "" : "Raum \(subject.room)"]
                    .filter { !$0.isEmpty }
                if !info.isEmpty {
                    Text(info.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }

    // MARK: Sections

    private var lessonsSection: some View {
        Section {
            ForEach(subject.sortedLessons) { lesson in
                Button {
                    sheet = .lesson(lesson)
                } label: {
                    HStack {
                        Text(Fmt.weekdayName(lesson.weekday))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(Fmt.clock(lesson.startMinute))–\(Fmt.clock(lesson.endMinute))")
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryInk)
                        if !lesson.room.isEmpty {
                            Text(lesson.room)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
            }
            .onDelete { offsets in
                let lessons = subject.sortedLessons
                for index in offsets { context.delete(lessons[index]) }
                context.commit()
            }
            Button {
                sheet = .newLesson(subject: subject, weekday: nil, period: nil)
            } label: {
                Label("Stunde hinzufügen", systemImage: "plus")
            }
        } header: {
            SectionTitle("Stundenplan")
        }
        .marginRow()
    }

    private var examsSection: some View {
        Section {
            ForEach(upcomingExams) { exam in
                Button {
                    sheet = .exam(exam)
                } label: {
                    examRow(exam)
                }
            }
            if !pastExams.isEmpty {
                DisclosureGroup("Vergangene Prüfungen (\(pastExams.count))", isExpanded: $showPastExams) {
                    ForEach(pastExams) { exam in
                        Button {
                            sheet = .exam(exam)
                        } label: {
                            examRow(exam)
                        }
                    }
                }
                .foregroundStyle(Palette.secondaryInk)
            }
            Button {
                sheet = .newExam(subject: subject, date: nil)
            } label: {
                Label("Prüfung eintragen", systemImage: "plus")
            }
        } header: {
            SectionTitle("Prüfungen")
        }
        .marginRow()
    }

    private func examRow(_ exam: Exam) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.displayTitle).foregroundStyle(Palette.ink)
                Text(Fmt.longDay(exam.date))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer()
            if exam.date >= today {
                Text(Fmt.relativeDay(exam.date))
                    .font(.subheadline)
                    .foregroundStyle(Palette.marginRed)
            }
        }
    }

    private var tasksSection: some View {
        Section {
            ForEach(openTasks) { task in
                NavigationLink(value: task) {
                    TaskRow(task: task, showSubject: false)
                }
            }
            Button {
                sheet = .newTask(subject: subject, dueDate: nil, exam: nil, topic: nil)
            } label: {
                Label("Aufgabe hinzufügen", systemImage: "plus")
            }
        } header: {
            SectionTitle("Aufgaben", trailing: doneCount > 0 ? "\(doneCount) erledigt" : nil)
        }
        .marginRow()
    }

    private var topicsSection: some View {
        Section {
            ForEach(subject.rootTopics) { topic in
                NavigationLink {
                    TopicDetailView(topic: topic)
                } label: {
                    TopicRow(topic: topic)
                }
            }
            .onMove { source, destination in
                var ordered = subject.rootTopics
                ordered.move(fromOffsets: source, toOffset: destination)
                for (index, topic) in ordered.enumerated() { topic.sortIndex = index }
                context.commit()
            }
            .onDelete { offsets in
                let topics = subject.rootTopics
                for index in offsets { context.delete(topics[index]) }
                context.commit()
            }
            Button {
                addingTopic = true
            } label: {
                Label("Thema hinzufügen", systemImage: "plus")
            }
        } header: {
            SectionTitle("Themen")
        } footer: {
            if subject.rootTopics.isEmpty {
                Text("Themen gliedern den Stoff, z. B. Algebra › Funktionen › Ableitungen. In Phase 3 bekommt jedes Thema einen Lernstand.")
            }
        }
        .marginRow()
    }

    // MARK: Actions

    private func addTopic() {
        let title = newTopicTitle.trimmingCharacters(in: .whitespaces)
        newTopicTitle = ""
        guard !title.isEmpty else { return }
        let topic = Topic(title: title, subject: nil, sortIndex: subject.rootTopics.count)
        context.insert(topic)
        topic.subject = subject
        context.commit()
    }

    private func deleteSubject() {
        let subject = subject
        let context = context
        dismiss()
        Deferred.afterDismiss {
            SubjectActions.delete(subject, context: context)
        }
    }
}

struct TopicRow: View {
    let topic: Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(topic.title).foregroundStyle(Palette.ink)
            let count = topic.children?.count ?? 0
            if count > 0 {
                Text("\(count) Unterthem\(count == 1 ? "a" : "en")")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}
