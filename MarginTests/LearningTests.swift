import SwiftData
import XCTest
@testable import Margin

final class StudyPlannerTests: XCTestCase {
    private let calendar = Calendar.school

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func topic(understanding: Int, importance: Int = 1, minutes: Int = 90) -> PlanTopic {
        PlanTopic(id: UUID(), importance: importance, understanding: understanding, estimatedMinutes: minutes)
    }

    func testPlanSpreadsSessionsAndRespectsDailyLimit() {
        let topics = [topic(understanding: 0), topic(understanding: 1), topic(understanding: 3)]
        let result = StudyPlanner.plan(topics: topics, examDate: date(2026, 11, 18), today: date(2026, 11, 4),
                                       dailyMinutes: 60, weekdays: Set(1...7))
        XCTAssertEqual(result.availableDays, 14)
        XCTAssertEqual(result.unscheduledMinutes, 0)
        let perDay = Dictionary(grouping: result.sessions) { $0.day }.mapValues { $0.reduce(0) { $0 + $1.minutes } }
        XCTAssertTrue(perDay.values.allSatisfy { $0 <= 60 }, "daily limit exceeded: \(perDay)")
        XCTAssertGreaterThanOrEqual(perDay.count, 7, "sessions should be spread, not crammed")
        XCTAssertTrue(result.sessions.allSatisfy { $0.day < date(2026, 11, 18) })
        XCTAssertEqual(result.sessions.last?.kind, .finalReview)
        XCTAssertEqual(result.sessions.last?.day, date(2026, 11, 17))
        XCTAssertTrue(result.sessions.contains { $0.kind == .mockTest })
    }

    func testEachTopicGoesLearnThenPractiseThenReview() {
        let weak = topic(understanding: 0, minutes: 120)
        let result = StudyPlanner.plan(topics: [weak], examDate: date(2026, 11, 20), today: date(2026, 11, 6),
                                       dailyMinutes: 45, weekdays: Set(1...7))
        let mine = result.sessions.filter { $0.topicID == weak.id }
        let lastLearn = mine.filter { $0.kind == .learn }.map(\.day).max()!
        let firstPractice = mine.filter { $0.kind == .practice }.map(\.day).min()!
        let lastPractice = mine.filter { $0.kind == .practice }.map(\.day).max()!
        let firstReview = mine.filter { $0.kind == .review }.map(\.day).min()!
        XCTAssertGreaterThan(firstPractice, lastLearn)
        XCTAssertGreaterThanOrEqual(calendar.daysBetween(lastPractice, firstReview), 2)
    }

    func testWeakImportantTopicsGetMoreTime() {
        XCTAssertGreaterThan(StudyPlanner.totalMinutes(for: topic(understanding: 0, importance: 2)),
                             StudyPlanner.totalMinutes(for: topic(understanding: 4, importance: 0)))
    }

    func testTooLittleTimeIsReportedNotCrammed() {
        let topics = (0..<6).map { _ in topic(understanding: 0, minutes: 240) }
        let result = StudyPlanner.plan(topics: topics, examDate: date(2026, 11, 7), today: date(2026, 11, 4),
                                       dailyMinutes: 30, weekdays: Set(1...7))
        XCTAssertGreaterThan(result.unscheduledMinutes, 0)
        let perDay = Dictionary(grouping: result.sessions) { $0.day }.mapValues { $0.reduce(0) { $0 + $1.minutes } }
        XCTAssertTrue(perDay.values.allSatisfy { $0 <= 30 })
    }

    func testOnlyChosenWeekdaysAreUsed() {
        let result = StudyPlanner.plan(topics: [topic(understanding: 1)], examDate: date(2026, 11, 30), today: date(2026, 11, 9),
                                       dailyMinutes: 60, weekdays: [1, 3])
        XCTAssertTrue(result.sessions.allSatisfy { [1, 3].contains(calendar.isoWeekday(of: $0.day)) })
    }

    func testExistingLoadFromOtherExamsCounts() {
        let busy = date(2026, 11, 10)
        let result = StudyPlanner.plan(topics: [topic(understanding: 0)], examDate: date(2026, 11, 12), today: busy,
                                       dailyMinutes: 60, weekdays: Set(1...7), existingLoad: [busy: 60])
        XCTAssertFalse(result.sessions.contains { $0.day == busy })
    }
}

final class SpacedRepetitionTests: XCTestCase {
    private let now = Calendar.school.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 15))!

    func testGoodAnswersGrowTheInterval() {
        var card = CardSchedule()
        card = SpacedRepetition.review(card, grade: .good, now: now)
        XCTAssertEqual(card.intervalDays, 1)
        card = SpacedRepetition.review(card, grade: .good, now: now)
        XCTAssertEqual(card.intervalDays, 4)
        card = SpacedRepetition.review(card, grade: .good, now: now)
        XCTAssertEqual(card.intervalDays, 10)
        XCTAssertEqual(card.ease, 2.5, accuracy: 0.001)
        XCTAssertEqual(Calendar.school.daysBetween(now, card.due), 10)
    }

    func testForgettingResetsAndComesBackSoon() {
        var card = CardSchedule(ease: 2.5, intervalDays: 20, repetitions: 5, lapses: 0, due: now)
        card = SpacedRepetition.review(card, grade: .again, now: now)
        XCTAssertEqual(card.repetitions, 0)
        XCTAssertEqual(card.lapses, 1)
        XCTAssertLessThan(card.ease, 2.5)
        XCTAssertLessThan(card.due.timeIntervalSince(now), 3600)
    }

    func testEaseNeverDropsBelowMinimum() {
        var card = CardSchedule(ease: 1.35, intervalDays: 3, repetitions: 3, lapses: 0, due: now)
        card = SpacedRepetition.review(card, grade: .hard, now: now)
        XCTAssertGreaterThanOrEqual(card.ease, 1.3)
    }
}

final class ReadinessTests: XCTestCase {
    private let now = Calendar.school.date(from: DateComponents(year: 2026, month: 11, day: 2))!

    func testUnderstandingMattersMoreThanFinishedMaterial() {
        let finishedButLost = ReadinessInput(id: UUID(), importance: 1, understanding: 0, completion: 1, lastStudied: now, scores: [])
        let understood = ReadinessInput(id: UUID(), importance: 1, understanding: 4, completion: 0.3, lastStudied: now, scores: [0.9])
        let result = Readiness.evaluate([finishedButLost, understood], now: now)
        XCTAssertLessThan(result.topics[0].score, result.topics[1].score)
        XCTAssertEqual(result.topics[0].reason, "Material fertig, aber noch nicht verstanden")
        XCTAssertEqual(result.topics[1].state, .confident)
    }

    func testOldKnowledgeFadesAndNeedsReview() {
        let fresh = ReadinessInput(id: UUID(), importance: 1, understanding: 3, completion: 1, lastStudied: now, scores: [])
        let old = ReadinessInput(id: UUID(), importance: 1, understanding: 3, completion: 1,
                                 lastStudied: Calendar.school.addingDays(-30, to: now), scores: [])
        let result = Readiness.evaluate([fresh, old], now: now)
        XCTAssertGreaterThan(result.topics[0].score, result.topics[1].score)
        XCTAssertEqual(result.topics[1].state, .needsReview)
    }

    func testPoorPracticeLowersReadiness() {
        let a = ReadinessInput(id: UUID(), importance: 1, understanding: 3, completion: 1, lastStudied: now, scores: [0.95])
        let b = ReadinessInput(id: UUID(), importance: 1, understanding: 3, completion: 1, lastStudied: now, scores: [0.3])
        let result = Readiness.evaluate([a, b], now: now)
        XCTAssertGreaterThan(result.topics[0].score, result.topics[1].score)
        XCTAssertEqual(result.topics[1].reason, "Letzte Übung 30 %")
    }

    func testFlashcardsFromNoteLines() {
        let cards = NoteFlashcards.extract(from: "# Zellen\n- Mitose :: Zellteilung\nNormaler Text\nATP::Energieträger\n :: leer")
        XCTAssertEqual(cards.map(\.front), ["Mitose", "ATP"])
        XCTAssertEqual(cards.map(\.back), ["Zellteilung", "Energieträger"])
    }
}

@MainActor
final class LearningStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        ReminderService.isEnabled = false
        container = try Persistence.inMemoryContainer()
    }

    func testRegeneratingAPlanCreatesSessionsAndKeepsDoneOnes() throws {
        let math = SchoolSubject(name: "Mathematik", colorKey: "blue")
        context.insert(math)
        let topic = Topic(title: "Ableitungen", subject: nil)
        context.insert(topic)
        topic.subject = math
        let exam = Exam(title: "", kind: .classTest, date: Calendar.school.addingDays(10, to: .now), subject: nil)
        context.insert(exam)
        exam.subject = math
        try context.save()

        let plan = LearningStore.plan(for: exam, context: context)
        XCTAssertEqual(plan.topicUIDs, [topic.uid])
        let first = LearningStore.regenerate(exam: exam, context: context)
        XCTAssertFalse(first.sessions.isEmpty)
        let sessions = LearningStore.sessions(for: exam, context: context)
        XCTAssertEqual(sessions.count, first.sessions.count)

        LearningStore.complete(sessions[0], minutes: 30, context: context)
        LearningStore.regenerate(exam: exam, context: context)
        let after = LearningStore.sessions(for: exam, context: context)
        XCTAssertEqual(after.filter { $0.status == .done }.count, 1)
        XCTAssertNotNil(LearningStore.progress(for: topic.uid, context: context).lastStudied)
    }

    func testNoteLinesBecomeCardsAndKeepProgress() throws {
        let note = NoteDocument(title: "Bio")
        note.body = "Mitose :: Zellteilung\nATP :: Energie"
        context.insert(note)
        LearningStore.syncCards(for: note, context: context)
        var cards = try context.fetch(FetchDescriptor<Flashcard>())
        XCTAssertEqual(cards.count, 2)
        let mitose = try XCTUnwrap(cards.first { $0.front == "Mitose" })
        LearningStore.apply(.good, to: mitose)

        note.body = "Mitose :: Zellteilung mit gleichem Erbgut"
        LearningStore.syncCards(for: note, context: context)
        cards = try context.fetch(FetchDescriptor<Flashcard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].back, "Zellteilung mit gleichem Erbgut")
        XCTAssertEqual(cards[0].repetitions, 1, "progress of an edited card must be kept")
    }

    func testBackupKeepsLearningData() throws {
        let card = Flashcard(front: "A", back: "B")
        card.intervalDays = 7
        context.insert(card)
        let grade = Grade(subjectUID: UUID(), value: 2.3, kind: .oral)
        context.insert(grade)
        let session = StudySession(date: .now, minutes: 25, kind: .practice)
        session.status = .done
        context.insert(session)
        try context.save()

        let data = try BackupService.export(context: context, settings: nil)
        try BackupService.restore(BackupService.decode(data), context: context, settings: nil)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Flashcard>()).first?.intervalDays, 7)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Grade>()).first?.value, 2.3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudySession>()).first?.status, .done)
    }
}
