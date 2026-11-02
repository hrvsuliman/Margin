import SwiftData
import SwiftUI

/// An exam with its topics, understanding, readiness and learning plan.
struct ExamDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let exam: Exam
    var showsDoneButton = false

    @Query private var allSessions: [StudySession]
    @Query private var allProgress: [TopicProgress]
    @Query private var allResults: [PracticeResult]
    @Query private var plans: [ExamPlan]
    @Query private var allTopics: [Topic]

    @State private var editing = false
    @State private var pickingTopics = false
    @State private var focus: FocusRequest?
    @State private var lastResult: PlanResult?
    @State private var openedTopic: Topic?

    private var plan: ExamPlan? { plans.first { $0.examUID == exam.uid } }
    private var topics: [Topic] {
        guard let plan else { return [] }
        let byID = Dictionary(allTopics.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        return plan.topicUIDs.compactMap { byID[$0] }
    }
    private var sessions: [StudySession] {
        allSessions.filter { $0.examUID == exam.uid }.sorted { $0.date < $1.date }
    }
    private var readiness: (overall: Double, topics: [TopicReadiness]) {
        // Reading the queries keeps this up to date when progress changes.
        _ = allProgress.count + allResults.count
        return LearningStore.readiness(for: exam, context: context)
    }
    private var daysLeft: Int { Calendar.school.daysBetween(.now, exam.date) }

    var body: some View {
        let state = readiness
        List {
            Section {
                header(state.overall)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

            topicsSection(state.topics)
            planSection

            Section {
                NavigationLink {
                    FlashcardDeckView(scope: .subject(exam.subject?.uid), title: exam.subject?.name ?? "Karteikarten")
                } label: {
                    Label("Karteikarten zu diesem Fach", systemImage: "rectangle.on.rectangle.angled")
                }
                Button {
                    focus = FocusRequest(topicUID: nil, subjectUID: exam.subject?.uid, examUID: exam.uid, minutes: 25, session: nil)
                } label: {
                    Label("Freie Lernzeit starten", systemImage: "timer")
                }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(exam.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { ExamEditor(exam: exam) }
                .tint(Palette.marginRed)
        }
        .sheet(isPresented: $pickingTopics) {
            NavigationStack { ExamTopicPicker(exam: exam) }
                .tint(Palette.marginRed)
        }
        .sheet(item: $openedTopic) { topic in
            NavigationStack {
                List { TopicProgressSection(topicUID: topic.uid) }
                    .marginList()
                    .navigationTitle(topic.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { openedTopic = nil }
                        }
                    }
            }
            .tint(Palette.marginRed)
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $focus) { request in
            FocusView(request: request)
        }
    }

    private func header(_ overall: Double) -> some View {
        HStack(spacing: 16) {
            ReadinessRing(value: overall, size: 72, lineWidth: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(exam.displayTitle)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(Fmt.longDay(exam.date)) · \(daysLeft == 0 ? "heute" : daysLeft == 1 ? "morgen" : "in \(daysLeft) Tagen")")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                Text(topics.isEmpty ? "Noch keine Themen" : "vorbereitet")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    // MARK: Topics

    private func topicsSection(_ states: [TopicReadiness]) -> some View {
        Section {
            ForEach(topics) { topic in
                let progress = allProgress.first { $0.topicUID == topic.uid }
                let state = states.first { $0.id == topic.uid }
                Button {
                    openedTopic = topic
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(topic.title).foregroundStyle(Palette.ink)
                            if let state {
                                Text("\(state.state.title) · \(state.reason)")
                                    .font(.caption)
                                    .foregroundStyle(state.state.color)
                            }
                        }
                        Spacer()
                        UnderstandingDots(level: progress?.understanding ?? .notYet) { level in
                            LearningStore.setUnderstanding(level, topicUID: topic.uid, source: "manual", context: context)
                        }
                    }
                }
                .swipeActions {
                    Button("Entfernen", role: .destructive) { remove(topic) }
                }
            }
            Button {
                pickingTopics = true
            } label: {
                Label(topics.isEmpty ? "Themen auswählen" : "Themen ändern", systemImage: "checklist")
            }
        } header: {
            SectionTitle("Themen", trailing: topics.isEmpty ? nil : "\(topics.count)")
        } footer: {
            Text("Tippe auf die Punkte, um dein Verständnis einzustufen. Die Bereitschaft berücksichtigt Verständnis, Übungsergebnisse, erledigtes Material und wie lange du ein Thema nicht wiederholt hast.")
        }
        .marginRow()
    }

    private func remove(_ topic: Topic) {
        plan?.topicUIDs.removeAll { $0 == topic.uid }
        try? context.save()
    }

    // MARK: Plan

    private var planSection: some View {
        Section {
            let missed = sessions.filter { $0.status == .planned && $0.date < Calendar.school.startOfDay(for: .now) }
            if !missed.isEmpty {
                Button {
                    regenerate()
                } label: {
                    Label("\(missed.count) Einheit\(missed.count == 1 ? "" : "en") verpasst – Rest neu verteilen",
                          systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Palette.marginRed)
                }
            }
            if let lastResult, lastResult.unscheduledMinutes > 0 {
                Label("\(Fmt.duration(minutes: lastResult.unscheduledMinutes)) passen nicht in den Plan. Erlaube mehr Minuten pro Tag oder mehr Lerntage.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Palette.marginRed)
            }

            ForEach(groupedSessions, id: \.day) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Fmt.shortDay(group.day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Calendar.school.isDateInToday(group.day) ? Palette.marginRed : Palette.secondaryInk)
                    ForEach(group.sessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(.vertical, 2)
            }

            if let plan {
                Stepper(value: Binding(get: { plan.dailyMinutes }, set: { plan.dailyMinutes = $0; try? context.save() }),
                        in: 15...240, step: 15) {
                    LabeledContent("Höchstens pro Tag", value: Fmt.duration(minutes: plan.dailyMinutes))
                }
                weekdayChips(plan)
            }
            Button {
                regenerate()
            } label: {
                Label(sessions.isEmpty ? "Lernplan erstellen" : "Plan neu berechnen", systemImage: "wand.and.stars")
                    .font(.body.weight(.semibold))
            }
            .disabled(topics.isEmpty || daysLeft < 1)
        } header: {
            SectionTitle("Lernplan")
        } footer: {
            Text(topics.isEmpty
                 ? "Wähle zuerst die Themen der Prüfung aus."
                 : "Schwache und wichtige Themen kommen zuerst. Verstehen → Üben → Wiederholen, mit Abstand zwischen den Einheiten. Der Tag vor der Prüfung bleibt für eine lockere Wiederholung. Die Einheiten erscheinen auch im Kalender.")
        }
        .marginRow()
    }

    private struct DayGroup {
        let day: Date
        let sessions: [StudySession]
    }

    private var groupedSessions: [DayGroup] {
        let calendar = Calendar.school
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { DayGroup(day: $0, sessions: grouped[$0] ?? []) }
    }

    private func sessionRow(_ session: StudySession) -> some View {
        let name = session.topicUID.flatMap { id in allTopics.first { $0.uid == id }?.title }
        return HStack {
            SessionRow(session: session, topicName: name)
            if session.status == .planned {
                Button {
                    focus = FocusRequest(topicUID: session.topicUID, subjectUID: session.subjectUID, examUID: exam.uid,
                                         minutes: session.plannedMinutes, session: session)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.paper)
                        .frame(width: 30, height: 30)
                        .background(Palette.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einheit starten")
            }
        }
        .contextMenu {
            if session.status == .planned {
                Button {
                    LearningStore.complete(session, minutes: session.plannedMinutes, context: context)
                    Haptics.success()
                } label: { Label("Als erledigt markieren", systemImage: "checkmark") }
                Button {
                    session.status = .skipped
                    try? context.save()
                } label: { Label("Auslassen", systemImage: "forward") }
                Button {
                    session.date = Calendar.school.addingDays(1, to: session.date)
                    try? context.save()
                } label: { Label("Auf morgen verschieben", systemImage: "arrow.right") }
            } else {
                Button {
                    session.status = .planned
                    session.completedAt = nil
                    try? context.save()
                } label: { Label("Wieder öffnen", systemImage: "arrow.uturn.backward") }
            }
        }
    }

    private func weekdayChips(_ plan: ExamPlan) -> some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isOn = plan.studyWeekdays.contains(day)
                Button {
                    if isOn {
                        if plan.studyWeekdays.count > 1 { plan.studyWeekdays.removeAll { $0 == day } }
                    } else {
                        plan.studyWeekdays.append(day)
                    }
                    try? context.save()
                    Haptics.selection()
                } label: {
                    Text(Fmt.weekdayName(day, short: true))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(isOn ? Palette.paper : Palette.secondaryInk)
                        .background(isOn ? Palette.ink : Palette.ruling.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("Lerntage")
    }

    private func regenerate() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            lastResult = LearningStore.regenerate(exam: exam, context: context)
        }
        ReminderService.scheduleRefresh(context: context)
        Haptics.success()
    }
}

/// Choose which topics an exam covers; new topics can be added on the spot.
struct ExamTopicPicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let exam: Exam
    @State private var selected: Set<UUID> = []
    @State private var newTitle = ""

    private var candidates: [TopicOutline.Entry] {
        TopicOutline.flatten(exam.subject?.rootTopics ?? [])
    }

    var body: some View {
        List {
            if exam.subject == nil {
                Section {
                    Text("Ordne der Prüfung zuerst ein Fach zu (Bearbeiten), dann kannst du seine Themen auswählen.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                .marginRow()
            } else {
                Section {
                    ForEach(candidates, id: \.topic.uid) { entry in
                        Button {
                            if selected.contains(entry.topic.uid) { selected.remove(entry.topic.uid) } else { selected.insert(entry.topic.uid) }
                            Haptics.selection()
                        } label: {
                            HStack {
                                Text(String(repeating: "    ", count: entry.depth) + entry.topic.title)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Image(systemName: selected.contains(entry.topic.uid) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(entry.topic.uid) ? Palette.marginRed : Palette.faintInk)
                            }
                        }
                    }
                    HStack {
                        TextField("Neues Thema", text: $newTitle)
                            .onSubmit(addTopic)
                        Button("Hinzufügen", action: addTopic)
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Neue Themen werden auch beim Fach \(exam.subject?.name ?? "") gespeichert.")
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Themen der Prüfung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save)
            }
        }
        .onAppear {
            selected = Set(LearningStore.plan(for: exam, context: context).topicUIDs)
        }
    }

    private func addTopic() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let subject = exam.subject else { return }
        let topic = Topic(title: title, subject: nil, sortIndex: subject.rootTopics.count)
        context.insert(topic)
        topic.subject = subject
        try? context.save()
        selected.insert(topic.uid)
        newTitle = ""
    }

    private func save() {
        let plan = LearningStore.plan(for: exam, context: context)
        // Keep the subject's order.
        let order = candidates.map(\.topic.uid)
        plan.topicUIDs = order.filter { selected.contains($0) }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
