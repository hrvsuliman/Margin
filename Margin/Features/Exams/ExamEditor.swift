import SwiftData
import SwiftUI

/// Create or edit an exam. Phase 3 adds topics, understanding and a learning plan.
struct ExamEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]

    private let exam: Exam?
    @State private var draft: Draft
    @State private var confirmDelete = false

    struct Draft {
        var title = ""
        var kind: ExamKind = .classTest
        var subject: SchoolSubject?
        var day = Calendar.school.addingDays(7, to: Calendar.school.startOfDay(for: .now))
        var hasTime = false
        var time = Calendar.school.date(on: .now, minute: 8 * 60)
        var durationMinutes = 90
        var room = ""
        var notes = ""
        var reminderDaysBefore = 1
    }

    init(exam: Exam) {
        self.exam = exam
        var draft = Draft()
        draft.title = exam.title
        draft.kind = exam.kind
        draft.subject = exam.subject
        draft.day = Calendar.school.startOfDay(for: exam.date)
        draft.hasTime = exam.hasTime
        draft.time = exam.date
        draft.durationMinutes = exam.durationMinutes
        draft.room = exam.room
        draft.notes = exam.notes
        draft.reminderDaysBefore = exam.reminderDaysBefore
        _draft = State(initialValue: draft)
    }

    init(subject: SchoolSubject? = nil, date: Date? = nil) {
        self.exam = nil
        var draft = Draft()
        draft.subject = subject
        draft.kind = AppSettings.shared.schoolType.defaultExamKind
        if let date { draft.day = Calendar.school.startOfDay(for: date) }
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { exam == nil }
    private var canSave: Bool {
        draft.subject != nil || !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                Picker("Fach", selection: $draft.subject) {
                    Text("Kein Fach").tag(nil as SchoolSubject?)
                    ForEach(subjects) { subject in
                        Text(subject.name).tag(subject as SchoolSubject?)
                    }
                }
                Picker("Art", selection: $draft.kind) {
                    ForEach(ExamKind.allCases) { Text($0.title).tag($0) }
                }
                TextField("Titel (optional), z. B. Funktionen", text: $draft.title)
            } footer: {
                Text("Ohne Titel heißt die Prüfung „\(previewTitle)“.")
            }
            .marginRow()

            Section("Termin") {
                DatePicker("Datum", selection: $draft.day, displayedComponents: .date)
                Toggle("Uhrzeit festlegen", isOn: $draft.hasTime.animation())
                if draft.hasTime {
                    DatePicker("Beginn", selection: $draft.time, displayedComponents: .hourAndMinute)
                    Picker("Dauer", selection: $draft.durationMinutes) {
                        ForEach([20, 30, 45, 60, 90, 120, 135, 180, 240, 300], id: \.self) {
                            Text(Fmt.duration(minutes: $0)).tag($0)
                        }
                    }
                }
                TextField("Raum", text: $draft.room)
            }
            .marginRow()

            Section("Erinnerung") {
                Picker("Erinnern", selection: $draft.reminderDaysBefore) {
                    Text("Keine").tag(-1)
                    Text("1 Tag vorher").tag(1)
                    Text("2 Tage vorher").tag(2)
                    Text("3 Tage vorher").tag(3)
                    Text("1 Woche vorher").tag(7)
                    Text("2 Wochen vorher").tag(14)
                }
            }
            .marginRow()

            Section("Notizen") {
                TextField("Themen, erlaubte Hilfsmittel …", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
            .marginRow()

            if let exam, !(exam.tasks ?? []).isEmpty {
                Section("Vorbereitung") {
                    ForEach(exam.tasks ?? []) { task in
                        Label(task.title, systemImage: task.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isDone ? Palette.secondaryInk : Palette.ink)
                    }
                }
                .marginRow()
            }

            if !isNew {
                Section {
                    Button("Prüfung löschen", role: .destructive) { confirmDelete = true }
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle(isNew ? "Neue Prüfung" : "Prüfung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).disabled(!canSave)
            }
        }
        .confirmationDialog("Prüfung löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: delete)
        } message: {
            Text("Zugeordnete Aufgaben bleiben erhalten.")
        }
    }

    private var previewTitle: String {
        [draft.kind.title, draft.subject?.name].compactMap { $0 }.joined(separator: " ")
    }

    private func save() {
        let calendar = Calendar.school
        let date = draft.hasTime
            ? calendar.date(on: draft.day, minute: calendar.minuteOfDay(draft.time))
            : calendar.startOfDay(for: draft.day)
        let target = exam ?? Exam(title: "", kind: draft.kind, date: date, subject: nil)
        if exam == nil { context.insert(target) }
        target.title = draft.title.trimmingCharacters(in: .whitespaces)
        target.kind = draft.kind
        target.subject = draft.subject
        target.date = date
        target.hasTime = draft.hasTime
        target.durationMinutes = draft.durationMinutes
        target.room = draft.room
        target.notes = draft.notes
        target.reminderDaysBefore = draft.reminderDaysBefore
        context.commit()
        Haptics.success()
        dismiss()
    }

    private func delete() {
        guard let exam else { return }
        let context = context
        dismiss()
        Deferred.afterDismiss {
            context.delete(exam)
            context.commit()
        }
    }
}
