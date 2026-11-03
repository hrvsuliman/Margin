import SwiftData
import SwiftUI

struct CalendarScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case month, week, day
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: "Monat"
            case .week: "Woche"
            case .day: "Tag"
            }
        }
    }

    @Query private var lessons: [Lesson]
    @Query private var exams: [Exam]
    @Query private var tasks: [SchoolTask]
    @Query private var events: [CalendarEvent]
    @Query private var holidays: [Holiday]
    @Query private var sessions: [StudySession]
    @Query private var entries: [TimetableEntry]
    @Query private var topics: [Topic]
    @Query private var subjects: [SchoolSubject]
    @Binding var plannerMode: String

    @State private var mode: Mode = .month
    @State private var selected = Calendar.school.startOfDay(for: .now)
    @State private var sheet: EditorSheet?

    private var agenda: Agenda {
        Agenda(lessons: lessons, exams: exams, tasks: tasks, events: events, holidays: holidays,
               sessions: sessions, entries: entries, topics: topics, subjects: subjects)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Ansicht", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                switch mode {
                case .month:
                    MonthCalendar(selected: $selected, agenda: agenda, open: open)
                case .week:
                    WeekCalendar(selected: $selected, agenda: agenda, open: open) { day in
                        selected = day
                        withAnimation(.easeInOut(duration: 0.2)) { mode = .day }
                    }
                case .day:
                    DayCalendar(selected: $selected, agenda: agenda, open: open)
                }
            }
            .background(Palette.paper)
            .navigationTitle("Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PlannerSwitch(mode: $plannerMode)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Heute") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            selected = Calendar.school.startOfDay(for: .now)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            sheet = .newEvent(date: selected)
                        } label: {
                            Label("Termin", systemImage: "calendar.badge.plus")
                        }
                        Button {
                            sheet = .newTask(subject: nil, dueDate: selected, exam: nil, topic: nil)
                        } label: {
                            Label("Aufgabe", systemImage: "checklist")
                        }
                        Button {
                            sheet = .newExam(subject: nil, date: selected)
                        } label: {
                            Label("Prüfung", systemImage: "list.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neu")
                }
            }
            .editorSheet($sheet)
        }
    }

    private func open(_ source: AgendaSource) {
        sheet = EditorSheet.open(source)
    }
}

// MARK: - Shared pieces

/// Moves tasks, exams and single events to another day from a context menu.
enum Reschedule {
    static func canShift(_ source: AgendaSource) -> Bool {
        switch source {
        case .task, .exam, .session: true
        case .event(let event): event.recurrence == .never
        case .lesson, .holiday, .entry: false
        }
    }

    @MainActor
    static func shift(_ source: AgendaSource, days: Int, context: ModelContext) {
        let calendar = Calendar.school
        switch source {
        case .task(let task):
            if let due = task.dueDate { task.dueDate = calendar.addingDays(days, to: due) }
            if let reminder = task.reminderDate { task.reminderDate = calendar.addingDays(days, to: reminder) }
        case .exam(let exam):
            exam.date = calendar.addingDays(days, to: exam.date)
        case .event(let event):
            event.start = calendar.addingDays(days, to: event.start)
            event.end = calendar.addingDays(days, to: event.end)
        case .session(let session):
            session.date = calendar.addingDays(days, to: session.date)
        case .lesson, .holiday, .entry:
            return
        }
        Haptics.success()
        context.commit()
    }
}

/// The list of entries for one day, used under the month grid.
struct DayAgendaList: View {
    @Environment(\.modelContext) private var context
    let day: Date
    let agenda: Agenda
    let open: (AgendaSource) -> Void

    var body: some View {
        let items = agenda.items(on: day)
        List {
            Section {
                if items.isEmpty {
                    Text("Keine Einträge")
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(items) { item in
                    Button {
                        open(item.source)
                    } label: {
                        AgendaRow(item: item)
                    }
                    .contextMenu {
                        if Reschedule.canShift(item.source) {
                            Button {
                                Reschedule.shift(item.source, days: 1, context: context)
                            } label: {
                                Label("Einen Tag später", systemImage: "arrow.right")
                            }
                            Button {
                                Reschedule.shift(item.source, days: 7, context: context)
                            } label: {
                                Label("Eine Woche später", systemImage: "arrow.right.to.line")
                            }
                            Button {
                                Reschedule.shift(item.source, days: -1, context: context)
                            } label: {
                                Label("Einen Tag früher", systemImage: "arrow.left")
                            }
                        }
                    }
                }
            } header: {
                SectionTitle(Fmt.longDay(day))
            }
            .marginRow()
        }
        .marginList()
    }
}
