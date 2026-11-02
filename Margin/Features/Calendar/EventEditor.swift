import SwiftData
import SwiftUI

/// Create or edit a calendar event (personal, school, project, presentation …).
struct EventEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]

    private let event: CalendarEvent?
    @State private var draft: Draft
    @State private var confirmDelete = false

    struct Draft {
        var title = ""
        var category: EventCategory = .personal
        var subject: SchoolSubject?
        var isAllDay = false
        var start = Date.now
        var end = Date.now.addingTimeInterval(3600)
        var recurrence: Recurrence = .never
        var hasRecurrenceEnd = false
        var recurrenceEnd = Calendar.school.addingDays(90, to: .now)
        var location = ""
        var notes = ""
        var reminderMinutesBefore = -1
    }

    init(event: CalendarEvent) {
        self.event = event
        var draft = Draft()
        draft.title = event.title
        draft.category = event.category
        draft.subject = event.subject
        draft.isAllDay = event.isAllDay
        draft.start = event.start
        draft.end = event.end
        draft.recurrence = event.recurrence
        draft.hasRecurrenceEnd = event.recurrenceEnd != nil
        draft.recurrenceEnd = event.recurrenceEnd ?? draft.recurrenceEnd
        draft.location = event.location
        draft.notes = event.notes
        draft.reminderMinutesBefore = event.reminderMinutesBefore
        _draft = State(initialValue: draft)
    }

    init(date: Date? = nil) {
        self.event = nil
        var draft = Draft()
        let calendar = Calendar.school
        let now = Date.now
        // Next full hour, on the chosen day.
        let hour = min(calendar.component(.hour, from: now) + 1, 22)
        let day = date ?? now
        draft.start = calendar.date(on: day, minute: hour * 60)
        draft.end = draft.start.addingTimeInterval(3600)
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { event == nil }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("Titel", text: $draft.title)
                    .font(.body.weight(.medium))
                Picker("Kategorie", selection: $draft.category) {
                    ForEach(EventCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }
                Picker("Fach", selection: $draft.subject) {
                    Text("Kein Fach").tag(nil as SchoolSubject?)
                    ForEach(subjects) { subject in
                        Text(subject.name).tag(subject as SchoolSubject?)
                    }
                }
                TextField("Ort", text: $draft.location)
            }
            .marginRow()

            Section {
                Toggle("Ganztägig", isOn: $draft.isAllDay.animation())
                DatePicker("Beginn", selection: $draft.start,
                           displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ende", selection: $draft.end, in: draft.start...,
                           displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
            }
            .marginRow()

            Section {
                Picker("Wiederholen", selection: $draft.recurrence.animation()) {
                    ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
                }
                if draft.recurrence != .never {
                    Toggle("Endet", isOn: $draft.hasRecurrenceEnd.animation())
                    if draft.hasRecurrenceEnd {
                        DatePicker("Letzter Tag", selection: $draft.recurrenceEnd, in: draft.start...,
                                   displayedComponents: .date)
                    }
                }
            } footer: {
                if draft.recurrence != .never && !isNew {
                    Text("Änderungen gelten für alle Termine dieser Serie.")
                }
            }
            .marginRow()

            Section {
                Picker("Erinnerung", selection: $draft.reminderMinutesBefore) {
                    Text("Keine").tag(-1)
                    Text("Zu Beginn").tag(0)
                    Text("5 Minuten vorher").tag(5)
                    Text("15 Minuten vorher").tag(15)
                    Text("30 Minuten vorher").tag(30)
                    Text("1 Stunde vorher").tag(60)
                    Text("1 Tag vorher").tag(1440)
                }
            }
            .marginRow()

            Section("Notizen") {
                TextField("Notizen", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
            .marginRow()

            if !isNew {
                Section {
                    Button(draft.recurrence == .never ? "Termin löschen" : "Serie löschen", role: .destructive) {
                        confirmDelete = true
                    }
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle(isNew ? "Neuer Termin" : "Termin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).disabled(!canSave)
            }
        }
        .onChange(of: draft.start) { oldValue, newValue in
            // Keep the duration when the start moves.
            let duration = max(0, draft.end.timeIntervalSince(oldValue))
            draft.end = newValue.addingTimeInterval(duration)
        }
        .confirmationDialog("Termin löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: delete)
        }
    }

    private func save() {
        let calendar = Calendar.school
        let start = draft.isAllDay ? calendar.startOfDay(for: draft.start) : draft.start
        var end = draft.isAllDay ? calendar.startOfDay(for: draft.end) : draft.end
        if end < start { end = start }

        let target = event ?? CalendarEvent(title: "", start: start, end: end, category: draft.category)
        if event == nil { context.insert(target) }
        target.title = draft.title.trimmingCharacters(in: .whitespaces)
        target.category = draft.category
        target.subject = draft.subject
        target.isAllDay = draft.isAllDay
        target.start = start
        target.end = end
        target.recurrence = draft.recurrence
        target.recurrenceEnd = draft.recurrence != .never && draft.hasRecurrenceEnd
            ? calendar.startOfDay(for: draft.recurrenceEnd) : nil
        target.location = draft.location
        target.notes = draft.notes
        target.reminderMinutesBefore = draft.reminderMinutesBefore
        context.commit()
        Haptics.success()
        dismiss()
    }

    private func delete() {
        guard let event else { return }
        let context = context
        dismiss()
        Deferred.afterDismiss {
            context.delete(event)
            context.commit()
        }
    }
}
