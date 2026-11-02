import SwiftData
import SwiftUI

/// School holidays and other days without lessons. On these days the
/// timetable is hidden in the calendar and on the Today screen.
struct HolidaysView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Holiday.start) private var holidays: [Holiday]
    @State private var sheet: EditorSheet?

    var body: some View {
        List {
            if holidays.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "sun.max",
                        title: "Keine Ferien eingetragen",
                        message: "Trag Ferien und bewegliche Ferientage ein. Dann zeigt Margin an diesen Tagen keinen Unterricht.",
                        actionTitle: "Ferien eintragen",
                        action: { sheet = .holiday(nil) }
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(holidays) { holiday in
                        Button {
                            sheet = .holiday(holiday)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holiday.name.isEmpty ? "Schulfrei" : holiday.name)
                                    .foregroundStyle(Palette.ink)
                                Text(rangeText(holiday))
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(holidays[index]) }
                        context.commit()
                    }
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Ferien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheet = .holiday(nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ferien eintragen")
            }
        }
        .editorSheet($sheet)
    }

    private func rangeText(_ holiday: Holiday) -> String {
        let calendar = Calendar.school
        if calendar.isDate(holiday.start, inSameDayAs: holiday.end) {
            return Fmt.longDay(holiday.start)
        }
        let days = calendar.daysBetween(holiday.start, holiday.end) + 1
        return "\(Fmt.date(holiday.start)) – \(Fmt.date(holiday.end)) · \(days) Tage"
    }
}

struct HolidayEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let holiday: Holiday?
    @State private var name: String
    @State private var start: Date
    @State private var end: Date

    static let suggestions = ["Herbstferien", "Weihnachtsferien", "Winterferien", "Osterferien",
                              "Pfingstferien", "Sommerferien", "Beweglicher Ferientag", "Feiertag"]

    init(holiday: Holiday?) {
        self.holiday = holiday
        let today = Calendar.school.startOfDay(for: .now)
        _name = State(initialValue: holiday?.name ?? "")
        _start = State(initialValue: holiday?.start ?? today)
        _end = State(initialValue: holiday?.end ?? today)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, z. B. Herbstferien", text: $name)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            Button(suggestion) { name = suggestion }
                                .buttonStyle(.bordered)
                                .tint(Palette.secondaryInk)
                                .font(.caption)
                        }
                    }
                }
            }
            .marginRow()

            Section {
                DatePicker("Erster Tag", selection: $start, displayedComponents: .date)
                DatePicker("Letzter Tag", selection: $end, in: start..., displayedComponents: .date)
            } footer: {
                Text("Beide Tage zählen mit.")
            }
            .marginRow()

            if let holiday {
                Section {
                    Button("Löschen", role: .destructive) {
                        let context = context
                        dismiss()
                        Deferred.afterDismiss {
                            context.delete(holiday)
                            context.commit()
                        }
                    }
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle(holiday == nil ? "Ferien eintragen" : "Ferien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save)
            }
        }
        .onChange(of: start) {
            if end < start { end = start }
        }
    }

    private func save() {
        let calendar = Calendar.school
        let first = calendar.startOfDay(for: start)
        let last = max(first, calendar.startOfDay(for: end))
        let target = holiday ?? Holiday(name: "", start: first, end: last)
        if holiday == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.start = first
        target.end = last
        context.commit()
        Haptics.success()
        dismiss()
    }
}
