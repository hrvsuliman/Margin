import SwiftData
import SwiftUI

/// Create or edit a weekly lesson. Times can be picked by period ("3. Stunde")
/// from the bell schedule in Settings, or set exactly.
struct LessonEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]

    private let lesson: Lesson?
    @State private var draft: Draft
    @State private var confirmDelete = false
    @State private var savedCount = 0

    struct Draft {
        var subject: SchoolSubject?
        var weekday = 1
        var startMinute = 480
        var endMinute = 525
        var room = ""
        var note = ""
    }

    init(lesson: Lesson) {
        self.lesson = lesson
        _draft = State(initialValue: Draft(
            subject: lesson.subject, weekday: lesson.weekday, startMinute: lesson.startMinute,
            endMinute: lesson.endMinute, room: lesson.room, note: lesson.note
        ))
    }

    /// New lesson. `period` is a 0-based index into the bell schedule.
    init(subject: SchoolSubject? = nil, weekday: Int? = nil, period: Int? = nil) {
        self.lesson = nil
        var draft = Draft()
        draft.subject = subject
        draft.weekday = weekday ?? 1
        let periods = AppSettings.shared.periods
        if let period, periods.indices.contains(period) {
            draft.startMinute = periods[period].startMinute
            draft.endMinute = periods[period].endMinute
        } else if let first = periods.first {
            draft.startMinute = first.startMinute
            draft.endMinute = first.endMinute
        }
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { lesson == nil }
    private var canSave: Bool { draft.subject != nil && draft.endMinute > draft.startMinute }

    var body: some View {
        Form {
            Section {
                Picker("Fach", selection: $draft.subject) {
                    Text("Bitte wählen").tag(nil as SchoolSubject?)
                    ForEach(subjects) { subject in
                        Text(subject.name).tag(subject as SchoolSubject?)
                    }
                }
                Picker("Tag", selection: $draft.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Fmt.weekdayName(day)).tag(day)
                    }
                }
            }
            .marginRow()

            Section {
                if !settings.periods.isEmpty {
                    Picker("Von", selection: fromPeriod) {
                        Text("Eigene Zeit").tag(-1)
                        ForEach(settings.periods.indices, id: \.self) { index in
                            Text("\(index + 1). Stunde · \(Fmt.clock(settings.periods[index].startMinute))").tag(index)
                        }
                    }
                    Picker("Bis", selection: toPeriod) {
                        Text("Eigene Zeit").tag(-1)
                        ForEach(settings.periods.indices, id: \.self) { index in
                            Text("\(index + 1). Stunde · \(Fmt.clock(settings.periods[index].endMinute))").tag(index)
                        }
                    }
                }
                DatePicker("Beginn", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Ende", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
            } header: {
                Text("Zeit")
            } footer: {
                if draft.endMinute <= draft.startMinute {
                    Text("Das Ende muss nach dem Beginn liegen.")
                        .foregroundStyle(Palette.marginRed)
                } else {
                    Text("Die Stundenzeiten stellst du in den Einstellungen unter „Stundenraster“ ein.")
                }
            }
            .marginRow()

            Section {
                TextField("Raum", text: $draft.room)
                TextField("Notiz, z. B. Lehrkraft-Vertretung", text: $draft.note)
            }
            .marginRow()

            if isNew {
                Section {
                    Button {
                        saveAndContinue()
                    } label: {
                        Label("Sichern und nächste Stunde", systemImage: "plus.square.on.square")
                    }
                    .disabled(!canSave)
                } footer: {
                    if savedCount > 0 {
                        Text("\(savedCount) Stunde\(savedCount == 1 ? "" : "n") eingetragen.")
                    }
                }
                .marginRow()
            } else {
                Section {
                    Button("Stunde löschen", role: .destructive) { confirmDelete = true }
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle(isNew ? "Neue Stunde" : "Stunde")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(savedCount > 0 ? "Fertig" : "Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    write()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .confirmationDialog("Stunde löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: delete)
        }
    }

    // MARK: Bindings

    private var fromPeriod: Binding<Int> {
        Binding(
            get: { settings.periods.firstIndex { $0.startMinute == draft.startMinute } ?? -1 },
            set: { index in
                guard settings.periods.indices.contains(index) else { return }
                let period = settings.periods[index]
                draft.startMinute = period.startMinute
                if draft.endMinute <= draft.startMinute {
                    draft.endMinute = period.endMinute
                }
            }
        )
    }

    private var toPeriod: Binding<Int> {
        Binding(
            get: { settings.periods.firstIndex { $0.endMinute == draft.endMinute } ?? -1 },
            set: { index in
                guard settings.periods.indices.contains(index) else { return }
                draft.endMinute = settings.periods[index].endMinute
            }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<Draft, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.school.date(on: .now, minute: draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = Calendar.school.minuteOfDay($0) }
        )
    }

    // MARK: Actions

    private func write() {
        let target = lesson ?? Lesson(subject: nil, weekday: draft.weekday,
                                      startMinute: draft.startMinute, endMinute: draft.endMinute)
        if lesson == nil { context.insert(target) }
        target.subject = draft.subject
        target.weekday = draft.weekday
        target.startMinute = draft.startMinute
        target.endMinute = draft.endMinute
        target.room = draft.room
        target.note = draft.note
        context.commit()
        Haptics.success()
    }

    /// Saves, then prepares the following period(s) on the same day,
    /// keeping the length (a double lesson is followed by a double lesson).
    private func saveAndContinue() {
        write()
        savedCount += 1
        let periods = settings.periods.sorted { $0.startMinute < $1.startMinute }
        let length = draft.endMinute - draft.startMinute
        let span = max(1, periods.filter { $0.startMinute >= draft.startMinute && $0.endMinute <= draft.endMinute }.count)
        if let next = periods.firstIndex(where: { $0.startMinute >= draft.endMinute }) {
            draft.startMinute = periods[next].startMinute
            draft.endMinute = periods[min(next + span - 1, periods.count - 1)].endMinute
        } else {
            draft.startMinute = min(draft.endMinute, 24 * 60 - 1 - length)
            draft.endMinute = draft.startMinute + length
        }
        draft.room = ""
        draft.note = ""
    }

    private func delete() {
        guard let lesson else { return }
        let context = context
        dismiss()
        Deferred.afterDismiss {
            context.delete(lesson)
            context.commit()
        }
    }
}
