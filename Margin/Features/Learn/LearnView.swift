import Charts
import SwiftData
import SwiftUI

/// The Lernen tab: what to do next, exams with readiness, flashcards, focus and progress.
struct LearnView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exam.date) private var exams: [Exam]
    @Query private var cards: [Flashcard]
    @Query private var sessions: [StudySession]
    @Query private var progress: [TopicProgress]
    @Query private var results: [PracticeResult]
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]

    @State private var path = NavigationPath()
    @State private var focus: FocusRequest?
    @State private var review: ReviewRequest?
    @State private var sheet: EditorSheet?
    @State private var newCard = false
    @State private var showAssistant = false

    private var upcoming: [Exam] {
        let today = Calendar.school.startOfDay(for: .now)
        return exams.filter { $0.date >= today }
    }
    private var dueCards: [Flashcard] { cards.filter { $0.due <= .now } }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Reading the queries keeps the next step fresh.
                let _ = sessions.count + progress.count + results.count + cards.count
                if let step = LearningStore.nextStep(context) {
                    Section {
                        NextStepCard(step: step) { perform(step.action) }
                    }
                    .marginRow()
                }

                Section {
                    Button {
                        showAssistant = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(Palette.marginRed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Claude fragen").foregroundStyle(Palette.ink)
                                Text("Erklären, zusammenfassen, Karteikarten, abfragen – mit deinem Material")
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
                .marginRow()

                examsSection
                cardsSection

                Section {
                    Button {
                        focus = FocusRequest(topicUID: nil, subjectUID: nil, examUID: nil, minutes: 25, session: nil)
                    } label: {
                        Label("Fokuszeit starten", systemImage: "timer")
                    }
                    NavigationLink {
                        StatsView()
                    } label: {
                        weekRow
                    }
                } header: {
                    SectionTitle("Lernzeit")
                }
                .marginRow()
            }
            .marginList()
            .navigationTitle("Lernen")
            .navigationDestination(for: Exam.self) { exam in
                ExamDetailView(exam: exam)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            sheet = .newExam(subject: nil, date: nil)
                        } label: {
                            Label("Prüfung", systemImage: "list.clipboard")
                        }
                        Button {
                            newCard = true
                        } label: {
                            Label("Karteikarte", systemImage: "rectangle.on.rectangle.angled")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neu")
                }
            }
            .editorSheet($sheet)
            .sheet(isPresented: $newCard) {
                NavigationStack { FlashcardEditor(card: nil, scope: .all) }
                    .tint(Palette.marginRed)
            }
            .fullScreenCover(item: $focus) { FocusView(request: $0) }
            .fullScreenCover(item: $review) { FlashcardReviewView(cards: $0.cards) }
            .sheet(isPresented: $showAssistant) { AssistantView() }
        }
    }

    // MARK: Sections

    private var examsSection: some View {
        Section {
            if upcoming.isEmpty {
                Button {
                    sheet = .newExam(subject: nil, date: nil)
                } label: {
                    Label("Prüfung eintragen", systemImage: "plus")
                }
            }
            ForEach(upcoming) { exam in
                NavigationLink(value: exam) {
                    ExamReadinessRow(exam: exam, readiness: LearningStore.readiness(for: exam, context: context).overall)
                }
            }
        } header: {
            SectionTitle("Prüfungen")
        } footer: {
            if !upcoming.isEmpty {
                Text("Die Zahl im Ring zeigt, wie gut du vorbereitet bist – aus Verständnis, Übung und Wiederholung.")
            }
        }
        .marginRow()
    }

    private var cardsSection: some View {
        Section {
            if !dueCards.isEmpty {
                Button {
                    review = ReviewRequest(cards: dueCards.sorted { $0.due < $1.due })
                } label: {
                    Label("\(dueCards.count) Karte\(dueCards.count == 1 ? "" : "n") fällig – jetzt lernen",
                          systemImage: "rectangle.on.rectangle.angled")
                        .font(.body.weight(.semibold))
                }
            }
            ForEach(decks, id: \.id) { deck in
                NavigationLink {
                    FlashcardDeckView(scope: .subject(deck.subjectUID), title: deck.title)
                } label: {
                    HStack {
                        SubjectDot(color: deck.color, size: 10)
                        Text(deck.title).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(deck.due > 0 ? "\(deck.due) fällig · \(deck.count)" : "\(deck.count)")
                            .font(.caption)
                            .foregroundStyle(deck.due > 0 ? Palette.marginRed : Palette.secondaryInk)
                    }
                }
            }
            NavigationLink {
                FlashcardDeckView(scope: .all, title: "Alle Karten")
            } label: {
                Label("Alle Karten", systemImage: "square.stack")
            }
        } header: {
            SectionTitle("Karteikarten", trailing: cards.isEmpty ? nil : "\(cards.count)")
        } footer: {
            if cards.isEmpty {
                Text("Tipp: Schreib in einer Notiz „Begriff :: Erklärung“ – daraus wird automatisch eine Karte, geschrieben in deiner Handschrift.")
            }
        }
        .marginRow()
    }

    private struct Deck {
        let id: String
        let subjectUID: UUID?
        let title: String
        let color: Color
        let count: Int
        let due: Int
    }

    private var decks: [Deck] {
        let now = Date.now
        var result: [Deck] = subjects.compactMap { subject in
            let list = cards.filter { $0.subjectUID == subject.uid }
            guard !list.isEmpty else { return nil }
            return Deck(id: subject.uid.uuidString, subjectUID: subject.uid, title: subject.name, color: subject.color.color,
                        count: list.count, due: list.filter { $0.due <= now }.count)
        }
        let loose = cards.filter { $0.subjectUID == nil }
        if !loose.isEmpty {
            result.append(Deck(id: "none", subjectUID: nil, title: "Ohne Fach", color: Palette.faintInk,
                               count: loose.count, due: loose.filter { $0.due <= now }.count))
        }
        return result
    }

    private var weekRow: some View {
        let week = LearningStore.week(containing: .now, context: context)
        return VStack(alignment: .leading, spacing: 3) {
            Text("Diese Woche: \(Fmt.duration(minutes: week.minutes))")
                .foregroundStyle(Palette.ink)
            Text("\(week.sessions) Einheiten · \(week.improvedTopics) Themen verbessert · \(week.cardsReviewed) Karten wiederholt")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    private func perform(_ action: NextStep.Action) {
        switch action {
        case .session(let session):
            focus = FocusRequest(topicUID: session.topicUID, subjectUID: session.subjectUID, examUID: session.examUID,
                                 minutes: session.plannedMinutes, session: session)
        case let .focus(topicUID, subjectUID, minutes):
            focus = FocusRequest(topicUID: topicUID, subjectUID: subjectUID, examUID: nil, minutes: minutes, session: nil)
        case .cards:
            review = ReviewRequest(cards: dueCards.sorted { $0.due < $1.due })
        case .exam(let exam):
            path.append(exam)
        }
    }
}

struct ExamReadinessRow: View {
    let exam: Exam
    let readiness: Double

    var body: some View {
        HStack(spacing: 12) {
            ReadinessRing(value: readiness, size: 42, lineWidth: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.displayTitle).foregroundStyle(Palette.ink)
                Text("\(Fmt.longDay(exam.date)) · \(Fmt.relativeDay(exam.date))")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

/// Learning time, practice results and understanding – progress you can see,
/// without streaks.
struct StatsView: View {
    @Query private var sessions: [StudySession]
    @Query(sort: \PracticeResult.date) private var results: [PracticeResult]
    @Query private var progress: [TopicProgress]
    @Query private var events: [UnderstandingEvent]
    @Query private var topics: [Topic]
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @State private var weeks = 4

    private var start: Date {
        Calendar.school.addingDays(-7 * (weeks - 1), to: Calendar.school.startOfWeek(for: .now))
    }

    private struct WeekBar: Identifiable {
        let id = UUID()
        let week: Date
        let subject: String
        let minutes: Int
    }

    private var bars: [WeekBar] {
        let calendar = Calendar.school
        var totals: [Date: [String: Int]] = [:]
        for session in sessions where session.status == .done {
            let when = session.completedAt ?? session.date
            guard when >= start else { continue }
            let week = calendar.startOfWeek(for: when)
            let name = subjects.first { $0.uid == session.subjectUID }?.name ?? "Ohne Fach"
            totals[week, default: [:]][name, default: 0] += session.actualMinutes
        }
        return totals.flatMap { week, bySubject in
            bySubject.map { WeekBar(week: week, subject: $0.key, minutes: $0.value) }
        }
        .sorted { $0.week < $1.week }
    }

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $weeks) {
                    Text("4 Wochen").tag(4)
                    Text("3 Monate").tag(13)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                let data = bars
                if data.isEmpty {
                    Text("Noch keine Lernzeit. Starte eine Fokuszeit oder hake eine Lerneinheit ab.")
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    Chart(data) { bar in
                        BarMark(x: .value("Woche", bar.week, unit: .weekOfYear), y: .value("Minuten", bar.minutes))
                            .foregroundStyle(by: .value("Fach", bar.subject))
                    }
                    .chartForegroundStyleScale(domain: subjectDomain(data), range: subjectColors(data))
                    .frame(height: 200)
                    LabeledContent("Gesamt", value: Fmt.duration(minutes: data.reduce(0) { $0 + $1.minutes }))
                }
            } header: {
                SectionTitle("Lernzeit pro Woche")
            }
            .marginRow()

            Section {
                let recent = results.filter { $0.date >= start }
                if recent.isEmpty {
                    Text("Noch keine Übungsergebnisse. Karteikarten und Quizze tragen hier ein.")
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    Chart(recent) { result in
                        LineMark(x: .value("Datum", result.date), y: .value("Ergebnis", result.score * 100))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Datum", result.date), y: .value("Ergebnis", result.score * 100))
                    }
                    .chartYScale(domain: 0...100)
                    .foregroundStyle(Palette.marginRed)
                    .frame(height: 160)
                }
            } header: {
                SectionTitle("Übungsergebnisse (%)")
            }
            .marginRow()

            Section {
                ForEach(Understanding.allCases.reversed()) { level in
                    let count = progress.filter { entry in
                        entry.understanding == level && topics.contains { $0.uid == entry.topicUID }
                    }.count
                    HStack {
                        UnderstandingDots(level: level)
                        Text(level.short).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(count)").monospacedDigit().foregroundStyle(Palette.secondaryInk)
                    }
                }
                let improved = improvedCount
                Text(improved == 0 ? "In diesem Zeitraum noch keine Verbesserung eingetragen." : "\(improved) Themen in diesem Zeitraum verbessert.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            } header: {
                SectionTitle("Verständnis deiner Themen")
            }
            .marginRow()

            Section {
                let weak = needsWork
                if weak.isEmpty {
                    Text("Nichts Dringendes.").foregroundStyle(Palette.secondaryInk)
                }
                ForEach(weak, id: \.0.uid) { topic, reason in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.title).foregroundStyle(Palette.ink)
                        Text("\(topic.subject?.name ?? "") · \(reason)")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            } header: {
                SectionTitle("Braucht noch Arbeit")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func subjectDomain(_ data: [WeekBar]) -> [String] {
        Array(Set(data.map(\.subject))).sorted()
    }

    private func subjectColors(_ data: [WeekBar]) -> [Color] {
        subjectDomain(data).map { name in subjects.first { $0.name == name }?.color.color ?? Palette.faintInk }
    }

    private var improvedCount: Int {
        var before: [UUID: Int] = [:], after: [UUID: Int] = [:]
        for event in events.sorted(by: { $0.date < $1.date }) {
            guard let id = event.topicUID else { continue }
            if event.date < start { before[id] = event.level } else { after[id] = event.level }
        }
        return after.filter { $0.value > (before[$0.key] ?? 0) }.count
    }

    private var needsWork: [(Topic, String)] {
        let now = Date.now
        return topics.compactMap { topic -> (Topic, String)? in
            guard let entry = progress.first(where: { $0.topicUID == topic.uid }) else { return nil }
            if entry.understandingRaw <= 1 && entry.importance >= 1 { return (topic, entry.understanding.title) }
            if let last = entry.lastStudied, Calendar.school.daysBetween(last, now) > 14 && entry.understandingRaw < 4 {
                return (topic, "seit \(Calendar.school.daysBetween(last, now)) Tagen nicht wiederholt")
            }
            return nil
        }
        .prefix(8)
        .map { $0 }
    }
}

/// A learning session opened from the calendar or Today.
struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var topics: [Topic]
    @Query private var exams: [Exam]
    let session: StudySession
    @State private var focus: FocusRequest?

    private var topicName: String? { session.topicUID.flatMap { id in topics.first { $0.uid == id }?.title } }
    private var exam: Exam? { session.examUID.flatMap { id in exams.first { $0.uid == id } } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(session.kind.title, systemImage: session.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(topicName ?? exam?.displayTitle ?? "Lernzeit")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("\(Fmt.longDay(session.date)) · \(session.plannedMinutes) Min.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                    if let exam {
                        Text("für \(exam.displayTitle) \(Fmt.relativeDay(exam.date))")
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            .listRowBackground(Color.clear)

            Section {
                if session.status == .planned {
                    Button {
                        focus = FocusRequest(topicUID: session.topicUID, subjectUID: session.subjectUID, examUID: session.examUID,
                                             minutes: session.plannedMinutes, session: session)
                    } label: {
                        Label("Jetzt starten", systemImage: "play.fill").font(.body.weight(.semibold))
                    }
                    Button {
                        LearningStore.complete(session, minutes: session.plannedMinutes, context: context)
                        Haptics.success()
                        dismiss()
                    } label: { Label("Schon erledigt", systemImage: "checkmark") }
                    Button {
                        session.date = Calendar.school.addingDays(1, to: session.date)
                        try? context.save()
                        dismiss()
                    } label: { Label("Auf morgen verschieben", systemImage: "arrow.right") }
                    Button {
                        session.status = .skipped
                        try? context.save()
                        dismiss()
                    } label: { Label("Auslassen", systemImage: "forward") }
                } else {
                    LabeledContent("Status", value: session.status == .done ? "Erledigt · \(session.actualMinutes) Min." : "Ausgelassen")
                    Button {
                        session.status = .planned
                        session.completedAt = nil
                        try? context.save()
                    } label: { Label("Wieder öffnen", systemImage: "arrow.uturn.backward") }
                }
            }
            .marginRow()

            Section {
                Button("Einheit löschen", role: .destructive) {
                    let session = session
                    let context = context
                    dismiss()
                    Deferred.afterDismiss {
                        context.delete(session)
                        try? context.save()
                    }
                }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Lerneinheit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .fullScreenCover(item: $focus, onDismiss: { if session.status == .done { dismiss() } }) {
            FocusView(request: $0)
        }
    }
}
