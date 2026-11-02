import Foundation
import SwiftData

/// The one thing to do next, shown on Today and in the Lernen tab.
struct NextStep {
    enum Action {
        case session(StudySession)
        case focus(topicUID: UUID?, subjectUID: UUID?, minutes: Int)
        case cards
        case exam(Exam)
    }

    let title: String
    let detail: String
    let symbol: String
    let action: Action
}

/// Reads and writes learning data, and connects it to the pure engines.
@MainActor
enum LearningStore {
    static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: Topics

    static func progress(for topicUID: UUID, context: ModelContext) -> TopicProgress {
        if let existing = all(TopicProgress.self, context).first(where: { $0.topicUID == topicUID }) {
            return existing
        }
        let created = TopicProgress(topicUID: topicUID)
        context.insert(created)
        return created
    }

    static func progressMap(_ context: ModelContext) -> [UUID: TopicProgress] {
        var map: [UUID: TopicProgress] = [:]
        for entry in all(TopicProgress.self, context) {
            if let id = entry.topicUID { map[id] = entry }
        }
        return map
    }

    static func setUnderstanding(_ level: Understanding, topicUID: UUID, source: String, context: ModelContext) {
        let entry = Self.progress(for: topicUID, context: context)
        guard entry.understanding != level || source != "manual" else { return }
        entry.understanding = level
        entry.updatedAt = .now
        context.insert(UnderstandingEvent(topicUID: topicUID, level: level.rawValue, source: source))
        try? context.save()
    }

    static func markStudied(topicUID: UUID?, context: ModelContext) {
        guard let topicUID else { return }
        let entry = Self.progress(for: topicUID, context: context)
        entry.lastStudied = .now
        entry.updatedAt = .now
    }

    // MARK: Exams

    static func plan(for exam: Exam, context: ModelContext) -> ExamPlan {
        if let existing = all(ExamPlan.self, context).first(where: { $0.examUID == exam.uid }) {
            return existing
        }
        let created = ExamPlan(examUID: exam.uid)
        // Start with all topics of the subject.
        created.topicUIDs = exam.subject?.rootTopics.map(\.uid) ?? []
        context.insert(created)
        return created
    }

    static func existingPlan(for exam: Exam, context: ModelContext) -> ExamPlan? {
        all(ExamPlan.self, context).first { $0.examUID == exam.uid }
    }

    static func topics(of plan: ExamPlan, context: ModelContext) -> [Topic] {
        let byID = Dictionary(all(Topic.self, context).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        return plan.topicUIDs.compactMap { byID[$0] }
    }

    static func sessions(for exam: Exam, context: ModelContext) -> [StudySession] {
        all(StudySession.self, context).filter { $0.examUID == exam.uid }.sorted { $0.date < $1.date }
    }

    /// Replaces all future, not yet done sessions of the exam with a fresh plan.
    @discardableResult
    static func regenerate(exam: Exam, context: ModelContext, now: Date = .now) -> PlanResult {
        let calendar = Calendar.school
        let examPlan = Self.plan(for: exam, context: context)
        let today = calendar.startOfDay(for: now)
        for session in sessions(for: exam, context: context) where session.status == .planned {
            context.delete(session)
        }

        // Time already planned for other exams counts against the daily limit.
        var load: [Date: Int] = [:]
        for session in all(StudySession.self, context) where session.examUID != exam.uid && session.status == .planned {
            load[calendar.startOfDay(for: session.date), default: 0] += session.plannedMinutes
        }

        let progress = progressMap(context)
        let planTopics = Self.topics(of: examPlan, context: context).map { topic -> PlanTopic in
            let entry = progress[topic.uid]
            return PlanTopic(id: topic.uid, importance: entry?.importance ?? 1,
                             understanding: entry?.understandingRaw ?? 0, estimatedMinutes: entry?.estimatedMinutes ?? 60)
        }
        let result = StudyPlanner.plan(
            topics: planTopics, examDate: exam.date, today: today, dailyMinutes: examPlan.dailyMinutes,
            weekdays: Set(examPlan.studyWeekdays), existingLoad: load, calendar: calendar
        )
        var perDay: [Date: Int] = [:]
        for planned in result.sessions {
            let offset = perDay[planned.day, default: 0]
            perDay[planned.day] = offset + planned.minutes + 10
            // Suggested start: 16:00, sessions one after another.
            let start = calendar.date(on: planned.day, minute: 16 * 60 + offset)
            let session = StudySession(date: start, minutes: planned.minutes, kind: planned.kind)
            session.examUID = exam.uid
            session.topicUID = planned.topicID
            session.subjectUID = exam.subject?.uid
            context.insert(session)
        }
        examPlan.generatedAt = now
        try? context.save()
        return result
    }

    /// Planned sessions before today that were neither done nor skipped.
    static func missedSessions(for exam: Exam, context: ModelContext, now: Date = .now) -> [StudySession] {
        let today = Calendar.school.startOfDay(for: now)
        return sessions(for: exam, context: context).filter { $0.status == .planned && $0.date < today }
    }

    static func readiness(for exam: Exam, context: ModelContext, now: Date = .now) -> (overall: Double, topics: [TopicReadiness]) {
        guard let examPlan = existingPlan(for: exam, context: context) else { return (0, []) }
        let progress = progressMap(context)
        let results = all(PracticeResult.self, context).sorted { $0.date > $1.date }
        let inputs = Self.topics(of: examPlan, context: context).map { topic -> ReadinessInput in
            let entry = progress[topic.uid]
            return ReadinessInput(
                id: topic.uid, importance: entry?.importance ?? 1, understanding: entry?.understandingRaw ?? 0,
                completion: entry?.completion ?? 0, lastStudied: entry?.lastStudied,
                scores: results.filter { $0.topicUID == topic.uid }.map(\.score)
            )
        }
        return Readiness.evaluate(inputs, now: now)
    }

    // MARK: Sessions

    /// Logs finished learning time (from the focus timer or a ticked-off session).
    static func complete(_ session: StudySession, minutes: Int, context: ModelContext) {
        session.status = .done
        session.actualMinutes = max(minutes, 1)
        session.completedAt = .now
        markStudied(topicUID: session.topicUID, context: context)
        try? context.save()
    }

    static func logFreeSession(topicUID: UUID?, subjectUID: UUID?, minutes: Int, context: ModelContext) {
        let session = StudySession(date: Date.now.addingTimeInterval(-Double(minutes) * 60), minutes: minutes, kind: .free)
        session.isPlanned = false
        session.topicUID = topicUID
        session.subjectUID = subjectUID
        context.insert(session)
        complete(session, minutes: minutes, context: context)
    }

    // MARK: Flashcards

    static func dueCards(_ context: ModelContext, now: Date = .now) -> [Flashcard] {
        all(Flashcard.self, context).filter { $0.due <= now }.sorted { $0.due < $1.due }
    }

    static func schedule(of card: Flashcard) -> CardSchedule {
        CardSchedule(ease: card.ease, intervalDays: card.intervalDays, repetitions: card.repetitions,
                     lapses: card.lapses, due: card.due)
    }

    static func apply(_ grade: ReviewGrade, to card: Flashcard, now: Date = .now) {
        let next = SpacedRepetition.review(schedule(of: card), grade: grade, now: now)
        card.ease = next.ease
        card.intervalDays = next.intervalDays
        card.repetitions = next.repetitions
        card.lapses = next.lapses
        card.due = next.due
        card.lastReviewed = now
    }

    /// Keeps a note's `Begriff :: Erklärung` cards in sync with its text.
    /// Learning progress of unchanged cards is kept.
    static func syncCards(for note: NoteDocument, context: ModelContext) {
        let extracted = NoteFlashcards.extract(from: note.body)
        let existing = all(Flashcard.self, context).filter { $0.noteUID == note.uid }
        var remaining = existing
        for pair in extracted {
            if let index = remaining.firstIndex(where: { $0.front == pair.front }) {
                remaining[index].back = pair.back
                remaining[index].subjectUID = note.subjectUID
                remaining[index].topicUID = note.topicUID
                remaining.remove(at: index)
            } else {
                let card = Flashcard(front: pair.front, back: pair.back)
                card.noteUID = note.uid
                card.subjectUID = note.subjectUID
                card.topicUID = note.topicUID
                context.insert(card)
            }
        }
        for stale in remaining { context.delete(stale) }
        try? context.save()
    }

    // MARK: Next step

    static func nextStep(_ context: ModelContext, now: Date = .now) -> NextStep? {
        let calendar = Calendar.school
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.addingDays(1, to: today)
        let topicNames = Dictionary(all(Topic.self, context).map { ($0.uid, $0.title) }, uniquingKeysWith: { a, _ in a })

        // 1. A session planned for today (or missed earlier).
        let open = all(StudySession.self, context)
            .filter { $0.status == .planned && $0.date < tomorrow }
            .sorted { $0.date < $1.date }
        if let session = open.first {
            let topic = session.topicUID.flatMap { topicNames[$0] }
            let missed = session.date < today
            return NextStep(
                title: [topic, session.kind.title].compactMap { $0 }.joined(separator: " – "),
                detail: "\(session.plannedMinutes) Min." + (missed ? " · verpasst, jetzt nachholen?" : " · heute geplant"),
                symbol: session.kind.symbol,
                action: .session(session)
            )
        }

        // 2. Flashcards due.
        let due = dueCards(context, now: now).count
        if due >= 5 {
            return NextStep(title: "\(due) Karteikarten wiederholen", detail: "ca. \(max(5, due / 2)) Min.",
                            symbol: "rectangle.on.rectangle.angled", action: .cards)
        }

        // 3. The weakest topic of the next exam.
        let exams = all(Exam.self, context).filter { $0.date >= today }.sorted { $0.date < $1.date }
        for exam in exams.prefix(3) {
            let state = Self.readiness(for: exam, context: context, now: now)
            if let weakest = state.topics.min(by: { $0.score < $1.score }), weakest.score < 0.8 {
                let name = topicNames[weakest.id] ?? "Thema"
                return NextStep(
                    title: "15 Min. \(name)",
                    detail: "\(exam.displayTitle) \(Fmt.relativeDay(exam.date, from: now)) · \(weakest.reason)",
                    symbol: "lightbulb",
                    action: .focus(topicUID: weakest.id, subjectUID: exam.subject?.uid, minutes: 15)
                )
            }
            if existingPlan(for: exam, context: context) == nil && calendar.daysBetween(now, exam.date) <= 21 {
                return NextStep(title: "Lernplan für \(exam.displayTitle)",
                                detail: "\(Fmt.relativeDay(exam.date, from: now)) · Themen eintragen, Plan erstellen",
                                symbol: "map", action: .exam(exam))
            }
        }

        if due > 0 {
            return NextStep(title: "\(due) Karteikarte\(due == 1 ? "" : "n") wiederholen", detail: "ein paar Minuten",
                            symbol: "rectangle.on.rectangle.angled", action: .cards)
        }
        return nil
    }

    // MARK: Week

    struct WeekSummary {
        var minutes = 0
        var sessions = 0
        var improvedTopics = 0
        var cardsReviewed = 0
        var bySubject: [UUID: Int] = [:]
    }

    static func week(containing date: Date, context: ModelContext) -> WeekSummary {
        let calendar = Calendar.school
        let start = calendar.startOfWeek(for: date)
        let end = calendar.addingDays(7, to: start)
        var summary = WeekSummary()
        for session in all(StudySession.self, context) where session.status == .done {
            let when = session.completedAt ?? session.date
            guard when >= start && when < end else { continue }
            summary.minutes += session.actualMinutes
            summary.sessions += 1
            if let subject = session.subjectUID { summary.bySubject[subject, default: 0] += session.actualMinutes }
        }
        // A topic counts as improved if its last level this week is above its level before.
        let events = all(UnderstandingEvent.self, context).sorted { $0.date < $1.date }
        var before: [UUID: Int] = [:], after: [UUID: Int] = [:]
        for event in events {
            guard let id = event.topicUID else { continue }
            if event.date < start { before[id] = event.level } else if event.date < end { after[id] = event.level }
        }
        summary.improvedTopics = after.filter { $0.value > (before[$0.key] ?? 0) }.count
        summary.cardsReviewed = all(Flashcard.self, context).filter { ($0.lastReviewed ?? .distantPast) >= start }.count
        return summary
    }
}
