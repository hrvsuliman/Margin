import SwiftData
import SwiftUI

/// The home screen: now and next, the day as a timeline, what's due, and in the evening a look at tomorrow.
/// Sections only appear when they have something to say.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query private var lessons: [Lesson]
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query private var tasks: [SchoolTask]
    @Query private var events: [CalendarEvent]
    @Query private var holidays: [Holiday]
    @Query private var sessions: [StudySession]
    @Query private var topics: [Topic]
    @Query private var cards: [Flashcard]
    @Query private var progress: [TopicProgress]
    @Query private var entries: [TimetableEntry]

    @State private var sheet: EditorSheet?
    @State private var showSettings = false
    @State private var focus: FocusRequest?
    @State private var review: ReviewRequest?
    @State private var openedSubject: SchoolSubject?
    @State private var recap: WeeklyRecap?

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
            .navigationDestination(item: $openedSubject) { subject in
                SubjectDetailView(subject: subject)
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
            .fullScreenCover(item: $focus) { FocusView(request: $0) }
            .fullScreenCover(item: $review) { FlashcardReviewView(cards: $0.cards) }
            .sheet(isPresented: Binding(get: { recap != nil }, set: { if !$0 { recap = nil } })) {
                if let recap { WeeklyRecapView(recap: recap) }
            }
        }
    }

    private var agenda: Agenda {
        Agenda(lessons: lessons, exams: exams, tasks: tasks, events: events, holidays: holidays,
               sessions: sessions, entries: entries, topics: topics, subjects: subjects)
    }

    private func perform(_ action: NextStep.Action) {
        switch action {
        case .session(let session):
            focus = FocusRequest(topicUID: session.topicUID, subjectUID: session.subjectUID, examUID: session.examUID,
                                 minutes: session.plannedMinutes, session: session)
        case let .focus(topicUID, subjectUID, minutes):
            focus = FocusRequest(topicUID: topicUID, subjectUID: subjectUID, examUID: nil, minutes: minutes, session: nil)
        case .cards:
            review = ReviewRequest(cards: cards.filter { $0.due <= .now }.sorted { $0.due < $1.due })
        case .exam(let exam):
            sheet = .exam(exam)
        }
    }

    // MARK: Content

    private func content(now: Date) -> some View {
        let calendar = Calendar.school
        let todayItems = agenda.items(on: now)
        let holiday = agenda.holiday(on: now)
        let todayLessons = todayItems.filter(\.isLesson)
        let timed = todayItems.filter { !$0.isAllDay && ($0.isLesson || $0.isSession || Self.isEvent($0)) }
        let allDayEvents = todayItems.filter { $0.isAllDay && Self.isEvent($0) }
        let rows = DayPlan.rows(items: timed, now: now, isToday: true)
        let hero = todayLessons.first { !$0.isDone && $0.end > now }
        let dueCardCount = cards.filter { $0.due <= now }.count
        let _ = progress.count
        let step = subjects.isEmpty ? nil : LearningStore.nextStep(context, now: now)
        let due = dueTasks(now: now)
        let upcomingExams = exams.filter {
            $0.date >= calendar.startOfDay(for: now) && calendar.daysBetween(now, $0.date) <= 28
        }
        let next = holiday == nil && hero == nil
            ? Timetable.currentOrNextLesson(lessons: lessons, holidays: holidays, now: now) : nil
        let schoolOver = todayLessons.allSatisfy { $0.end <= now }
        let tomorrow = calendar.component(.hour, from: now) >= 14 && schoolOver ? nextSchoolDay(after: now) : nil

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

            let changes = (todayItems + agenda.items(on: calendar.addingDays(1, to: now))).filter(\.isChange)
            if !changes.isEmpty {
                Section {
                    ForEach(changes) { item in
                        Button { sheet = EditorSheet.open(item.source) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol).foregroundStyle(Palette.marginRed)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.title) · \(Fmt.relativeDay(item.start, from: now).capitalized) \(Fmt.time(item.start))")
                                        .foregroundStyle(Palette.ink)
                                    Text(item.detail).font(.caption).foregroundStyle(Palette.secondaryInk)
                                }
                            }
                        }
                    }
                } header: {
                    SectionTitle("Änderungen", trailing: "WebUntis")
                }
                .marginRow()
            }

            if let hero {
                let subject = DayPlan.subject(of: hero, in: subjects)
                Section {
                    Button { open(hero) } label: {
                        NowCard(item: hero, subject: subject, now: now, badges: badges(for: hero))
                    }
                    .buttonStyle(.plain)
                }
                .marginRow()
            } else if let next {
                Section {
                    nextLessonRow(next, now: now)
                } header: {
                    SectionTitle(next.isNow ? "Jetzt" : "Als Nächstes")
                }
                .marginRow()
            }

            if let step {
                Section {
                    NextStepCard(step: step) { perform(step.action) }
                }
                .marginRow()
            }

            if !rows.isEmpty || !allDayEvents.isEmpty {
                Section {
                    if !allDayEvents.isEmpty {
                        FlowChips(items: allDayEvents.map { ($0.title, $0.color) })
                            .padding(.vertical, 6)
                    }
                    ForEach(rows) { row in
                        Button {
                            if case .item(let item) = row { open(item) }
                        } label: {
                            TimelineRowView(row: row, now: now, badges: badges(for: row))
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
                    }
                } header: {
                    SectionTitle("Tagesablauf", trailing: todayLessons.isEmpty ? nil : "\(todayLessons.count) Stunden")
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

            if dueCardCount > 0 {
                Section {
                    Button {
                        review = ReviewRequest(cards: cards.filter { $0.due <= now }.sorted { $0.due < $1.due })
                    } label: {
                        Label("\(dueCardCount) Karteikarte\(dueCardCount == 1 ? "" : "n") zum Wiederholen", systemImage: "rectangle.on.rectangle.angled")
                            .foregroundStyle(Palette.ink)
                    }
                }
                .marginRow()
            }

            if WeeklyRecap.isRecapTime(now), !subjects.isEmpty {
                let week = WeeklyRecap.make(for: now, context: context)
                Section {
                    Button { recap = week } label: { WeeklyRecapCard(recap: week) }
                        .buttonStyle(.plain)
                }
                .marginRow()
            }

            if let tomorrow {
                let dayItems = agenda.items(on: tomorrow)
                Section {
                    TomorrowCard(
                        day: tomorrow,
                        lessons: dayItems.filter(\.isLesson),
                        subjects: subjects,
                        dueCount: tasks.filter { !$0.isDone && $0.dueDate.map { calendar.isDate($0, inSameDayAs: tomorrow) } == true }.count,
                        exams: exams.filter { calendar.isDate($0.date, inSameDayAs: tomorrow) },
                        now: now
                    )
                } header: {
                    SectionTitle("Vorschau")
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

            if !subjects.isEmpty && rows.isEmpty && due.isEmpty && upcomingExams.isEmpty && tomorrow == nil {
                Section {
                    EmptyStateView(
                        symbol: holiday == nil ? "sun.max" : "beach.umbrella",
                        title: holiday == nil ? "Heute ist nichts geplant" : "Schulfrei",
                        message: lessons.isEmpty
                            ? "Trag deinen Stundenplan unter Lernen › Fächer und Themen › Stundenplan ein."
                            : "Neue Aufgaben, Prüfungen und Termine legst du mit + an."
                    )
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private static func isEvent(_ item: AgendaItem) -> Bool {
        if case .event = item.source { return true }
        return false
    }

    /// Lessons open their subject page (pinboard, progress); everything else its editor.
    private func open(_ item: AgendaItem) {
        if item.isLesson, let subject = DayPlan.subject(of: item, in: subjects) {
            openedSubject = subject
        } else {
            sheet = EditorSheet.open(item.source)
        }
    }

    /// "Hausaufgabe fällig" / "Arbeit" on a lesson when something is due for that subject that day.
    private func badges(for item: AgendaItem) -> [String] {
        guard item.isLesson, let subject = DayPlan.subject(of: item, in: subjects) else { return [] }
        let calendar = Calendar.school
        var result: [String] = []
        if exams.contains(where: { $0.subject?.uid == subject.uid && calendar.isDate($0.date, inSameDayAs: item.start) }) {
            result.append("Arbeit")
        }
        if tasks.contains(where: { task in
            !task.isDone && task.subject?.uid == subject.uid
                && task.dueDate.map { calendar.isDate($0, inSameDayAs: item.start) } == true
        }) {
            result.append("Hausaufgabe fällig")
        }
        return result
    }

    private func badges(for row: DayPlan.Row) -> [String] {
        if case .item(let item) = row { return badges(for: item) }
        return []
    }

    /// The next day (within a week) that has lessons.
    private func nextSchoolDay(after now: Date) -> Date? {
        let calendar = Calendar.school
        for offset in 1...7 {
            let day = calendar.addingDays(offset, to: calendar.startOfDay(for: now))
            if agenda.items(on: day).contains(where: \.isLesson) { return day }
        }
        return nil
    }

    private func header(now: Date, holiday: Holiday?, lessonCount: Int, dueCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting(now))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.marginRed)
            Text(Fmt.longDay(now))
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(summary(holiday: holiday, lessonCount: lessonCount, dueCount: dueCount, now: now))
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    private func greeting(_ now: Date) -> String {
        switch Calendar.school.component(.hour, from: now) {
        case 5..<11: "Guten Morgen"
        case 11..<17: "Hallo"
        case 17..<23: "Guten Abend"
        default: "Gute Nacht"
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
            ReadinessRing(value: LearningStore.readiness(for: exam, context: context, now: now).overall, size: 36, lineWidth: 3.5)
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
