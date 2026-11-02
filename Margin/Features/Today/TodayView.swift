import SwiftData
import SwiftUI

/// The home screen: what's on today, what's due, what's coming up.
/// Sections only appear when they have something to say.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query private var lessons: [Lesson]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query private var tasks: [SchoolTask]
    @Query private var events: [CalendarEvent]
    @Query private var holidays: [Holiday]

    @State private var sheet: EditorSheet?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
            .marginList()
            .navigationTitle("Heute")
            .navigationDestination(for: SchoolTask.self) { task in
                TaskDetailView(task: task)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
            .editorSheet($sheet)
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
                    .tint(Palette.marginRed)
            }
        }
    }

    private var agenda: Agenda {
        Agenda(lessons: lessons, exams: exams, tasks: tasks, events: events, holidays: holidays)
    }

    // MARK: Content

    private func content(now: Date) -> some View {
        let calendar = Calendar.school
        let todayItems = agenda.items(on: now)
        let holiday = agenda.holiday(on: now)
        let todayLessons = todayItems.filter(\.isLesson)
        let todayEvents = todayItems.filter { if case .event = $0.source { return true } else { return false } }
        let due = dueTasks(now: now)
        let upcomingExams = exams.filter {
            $0.date >= calendar.startOfDay(for: now) && calendar.daysBetween(now, $0.date) <= 28
        }
        let next = holiday == nil ? Timetable.currentOrNextLesson(lessons: lessons, holidays: holidays, now: now) : nil

        return List {
            Section {
                header(now: now, holiday: holiday, lessonCount: todayLessons.count, dueCount: due.count)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))

            if subjects.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "pencil.and.outline",
                        title: "Willkommen bei Margin",
                        message: "Leg zuerst deine Fächer an. Danach kannst du Stundenplan, Aufgaben und Prüfungen eintragen.",
                        actionTitle: "Fächer auswählen",
                        action: { sheet = .subjectTemplates }
                    )
                }
                .listRowBackground(Color.clear)
            }

            if let next {
                Section {
                    nextLessonRow(next, now: now)
                } header: {
                    SectionTitle(next.isNow ? "Jetzt" : "Als Nächstes")
                }
                .marginRow()
            }

            if !todayLessons.isEmpty {
                Section {
                    ForEach(todayLessons) { item in
                        Button { sheet = EditorSheet.open(item.source) } label: { AgendaRow(item: item, now: now) }
                    }
                } header: {
                    SectionTitle("Stundenplan", trailing: "\(todayLessons.count) Stunden")
                }
                .marginRow()
            }

            if !due.isEmpty {
                Section {
                    ForEach(due) { task in
                        NavigationLink(value: task) {
                            TaskRow(task: task)
                        }
                    }
                } header: {
                    SectionTitle("Fällig", trailing: "bis morgen")
                }
                .marginRow()
            }

            if !upcomingExams.isEmpty {
                Section {
                    ForEach(upcomingExams) { exam in
                        Button { sheet = .exam(exam) } label: { examRow(exam, now: now) }
                    }
                } header: {
                    SectionTitle("Prüfungen", trailing: "nächste 4 Wochen")
                }
                .marginRow()
            }

            if !todayEvents.isEmpty {
                Section {
                    ForEach(todayEvents) { item in
                        Button { sheet = EditorSheet.open(item.source) } label: { AgendaRow(item: item, now: now) }
                    }
                } header: {
                    SectionTitle("Termine")
                }
                .marginRow()
            }

            let later = laterThisWeek(now: now)
            if !later.isEmpty {
                Section {
                    ForEach(later) { task in
                        NavigationLink(value: task) {
                            TaskRow(task: task)
                        }
                    }
                } header: {
                    SectionTitle("Später diese Woche")
                }
                .marginRow()
            }

            if !subjects.isEmpty && todayLessons.isEmpty && due.isEmpty && todayEvents.isEmpty && upcomingExams.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: holiday == nil ? "sun.max" : "beach.umbrella",
                        title: holiday == nil ? "Heute ist nichts geplant" : "Schulfrei",
                        message: lessons.isEmpty
                            ? "Trag deinen Stundenplan unter Fächer › Stundenplan ein."
                            : "Neue Aufgaben, Prüfungen und Termine legst du mit + an."
                    )
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func header(now: Date, holiday: Holiday?, lessonCount: Int, dueCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.longDay(now))
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(summary(holiday: holiday, lessonCount: lessonCount, dueCount: dueCount, now: now))
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    private func summary(holiday: Holiday?, lessonCount: Int, dueCount: Int, now: Date) -> String {
        if let holiday {
            let name = holiday.name.isEmpty ? "Schulfrei" : holiday.name
            let left = Calendar.school.daysBetween(now, holiday.end)
            return left > 0 ? "\(name) · noch \(left) Tag\(left == 1 ? "" : "e")" : "\(name) · letzter Tag"
        }
        var parts: [String] = []
        if lessonCount > 0 { parts.append("\(lessonCount) Stunde\(lessonCount == 1 ? "" : "n")") }
        if dueCount > 0 { parts.append("\(dueCount) Aufgabe\(dueCount == 1 ? "" : "n") fällig") }
        if let exam = exams.first(where: { $0.date >= Calendar.school.startOfDay(for: now) }) {
            parts.append("\(exam.displayTitle) \(Fmt.relativeDay(exam.date, from: now))")
        }
        return parts.isEmpty ? "Kalenderwoche \(Calendar.school.component(.weekOfYear, from: now))" : parts.joined(separator: " · ")
    }

    private func nextLessonRow(_ next: Timetable.UpcomingLesson, now: Date) -> some View {
        Button {
            sheet = .lesson(next.lesson)
        } label: {
            HStack(spacing: 12) {
                MarginBar(color: next.lesson.subject?.color.color ?? SubjectColor.gray.color, width: 4)
                    .frame(height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(next.lesson.subject?.name ?? "Unterricht")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(nextLessonDetail(next, now: now))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer()
                if next.isNow {
                    let total = max(1, next.end.timeIntervalSince(next.start))
                    let done = now.timeIntervalSince(next.start)
                    ProgressRing(
                        progress: min(max(done / total, 0), 1),
                        color: next.lesson.subject?.color.color ?? Palette.marginRed
                    )
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("Stunde läuft")
                }
            }
        }
    }

    private func nextLessonDetail(_ next: Timetable.UpcomingLesson, now: Date) -> String {
        let room = next.lesson.room.isEmpty ? (next.lesson.subject?.room ?? "") : next.lesson.room
        let roomText = room.isEmpty ? "" : " · Raum \(room)"
        if next.isNow {
            let minutes = Int(next.end.timeIntervalSince(now) / 60)
            return "noch \(minutes) Min.\(roomText)"
        }
        let calendar = Calendar.school
        let day = calendar.isDate(next.start, inSameDayAs: now) ? "" : "\(Fmt.relativeDay(next.start, from: now).capitalized), "
        return "\(day)\(Fmt.time(next.start))–\(Fmt.time(next.end))\(roomText)"
    }

    private func examRow(_ exam: Exam, now: Date) -> some View {
        HStack(spacing: 12) {
            MarginBar(color: exam.subject?.color.color ?? Palette.marginRed)
                .frame(height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.displayTitle).foregroundStyle(Palette.ink)
                Text(Fmt.longDay(exam.date))
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer()
            let days = Calendar.school.daysBetween(now, exam.date)
            Text(days == 0 ? "heute" : days == 1 ? "morgen" : "\(days) Tage")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(days <= 3 ? Palette.marginRed : Palette.secondaryInk)
        }
    }

    // MARK: Data

    /// Open tasks that are overdue, due today or due tomorrow.
    private func dueTasks(now: Date) -> [SchoolTask] {
        let limit = Calendar.school.addingDays(2, to: Calendar.school.startOfDay(for: now))
        return tasks
            .filter { task in
                guard !task.isDone, let due = task.dueDate else { return false }
                return due < limit || task.isOverdue(now: now)
            }
            .sorted(by: TasksView.byDue)
    }

    /// Open tasks due after tomorrow but before the end of the week.
    private func laterThisWeek(now: Date) -> [SchoolTask] {
        let calendar = Calendar.school
        let from = calendar.addingDays(2, to: calendar.startOfDay(for: now))
        let to = calendar.addingDays(7, to: calendar.startOfWeek(for: now))
        return tasks
            .filter { task in
                guard !task.isDone, let due = task.dueDate else { return false }
                return due >= from && due < to
            }
            .sorted(by: TasksView.byDue)
    }

    private var addMenu: some View {
        Menu {
            Button {
                sheet = .newTask(subject: nil, dueDate: nil, exam: nil, topic: nil)
            } label: {
                Label("Aufgabe", systemImage: "checklist")
            }
            Button {
                sheet = .newExam(subject: nil, date: nil)
            } label: {
                Label("Prüfung", systemImage: "list.clipboard")
            }
            Button {
                sheet = .newEvent(date: nil)
            } label: {
                Label("Termin", systemImage: "calendar.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Neu")
    }
}
