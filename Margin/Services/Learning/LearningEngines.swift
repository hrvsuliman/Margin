import Foundation

// Pure learning logic: no SwiftUI, no database. Fully unit-tested.

// MARK: - Learning plan

struct PlanTopic: Equatable, Sendable {
    let id: UUID
    /// 0 = low, 1 = normal, 2 = high.
    let importance: Int
    /// 0 … 4, see `Understanding`.
    let understanding: Int
    let estimatedMinutes: Int
}

struct PlannedSession: Equatable, Sendable {
    let day: Date
    let topicID: UUID?
    let kind: SessionKind
    let minutes: Int
}

struct PlanResult: Equatable, Sendable {
    let sessions: [PlannedSession]
    /// Minutes that didn't fit into the available days.
    let unscheduledMinutes: Int
    let availableDays: Int
}

/// Builds a realistic learning plan for one exam.
///
/// - Weak and important topics need more time and are placed first.
/// - Each topic goes learn → practise → review, with at least a day between
///   practising and reviewing (spacing helps memory).
/// - Sessions are spread over the available days by always choosing the least
///   loaded day, so nothing piles up at the end. The daily limit is never
///   exceeded: what doesn't fit is reported instead of crammed in.
/// - The day before the exam is a light final review; with enough days a
///   practice test is placed shortly before.
enum StudyPlanner {
    static let maxChunk = 45
    static let minChunk = 15

    static func plan(
        topics: [PlanTopic],
        examDate: Date,
        today: Date,
        dailyMinutes: Int,
        weekdays: Set<Int>,
        existingLoad: [Date: Int] = [:],
        calendar: Calendar = .school
    ) -> PlanResult {
        let start = calendar.startOfDay(for: today)
        let examDay = calendar.startOfDay(for: examDate)
        var days: [Date] = []
        var day = start
        while day < examDay && days.count < 120 {
            if weekdays.contains(calendar.isoWeekday(of: day)) { days.append(day) }
            day = calendar.addingDays(1, to: day)
        }

        let needs = topics.map { (topic: $0, minutes: totalMinutes(for: $0)) }
        let total = needs.reduce(0) { $0 + $1.minutes }
        guard !days.isEmpty, dailyMinutes > 0 else {
            return PlanResult(sessions: [], unscheduledMinutes: total, availableDays: 0)
        }

        var load = days.map { existingLoad[$0] ?? 0 }
        var sessions: [PlannedSession] = []
        var unscheduled = 0

        func capacity(_ index: Int) -> Int { max(0, dailyMinutes - load[index]) }

        // Reserve the final review and the practice test first.
        let lastIndex = days.count - 1
        var reserved: Set<Int> = []
        if !topics.isEmpty {
            let finalMinutes = min(capacity(lastIndex), max(20, min(60, topics.count * 10)))
            if finalMinutes >= 10 {
                sessions.append(PlannedSession(day: days[lastIndex], topicID: nil, kind: .finalReview, minutes: finalMinutes))
                load[lastIndex] += finalMinutes
                reserved.insert(lastIndex)
            }
            if days.count >= 5 {
                let mockIndex = days.count - 3
                let mockMinutes = min(capacity(mockIndex), 45)
                if mockMinutes >= 20 {
                    sessions.append(PlannedSession(day: days[mockIndex], topicID: nil, kind: .mockTest, minutes: mockMinutes))
                    load[mockIndex] += mockMinutes
                }
            }
        }
        let workDays = days.indices.filter { !reserved.contains($0) || days.count == 1 }

        let ordered = needs.sorted { priority($0.topic) > priority($1.topic) }
        for entry in ordered {
            var earliest = 0
            var lastPractice = -1
            for (kind, minutes) in pieces(for: entry.topic, total: entry.minutes) {
                if kind == .review && lastPractice >= 0 {
                    earliest = max(earliest, min(lastPractice + 2, lastIndex))
                }
                let candidates = workDays.filter { $0 >= earliest }
                var placed = false
                // Least loaded day first; on a tie the earlier one.
                let sorted = candidates.sorted { (load[$0], $0) < (load[$1], $1) }
                if let index = sorted.first(where: { capacity($0) >= minutes }) {
                    sessions.append(PlannedSession(day: days[index], topicID: entry.topic.id, kind: kind, minutes: minutes))
                    load[index] += minutes
                    placed = true
                    earliest = kind == .learn ? index + 1 : index
                    if kind == .practice { lastPractice = index }
                } else if let index = sorted.first(where: { capacity($0) >= minChunk }) {
                    // Shorten the session to what still fits that day.
                    let fitted = capacity(index)
                    sessions.append(PlannedSession(day: days[index], topicID: entry.topic.id, kind: kind, minutes: fitted))
                    load[index] += fitted
                    unscheduled += minutes - fitted
                    placed = true
                    earliest = index
                    if kind == .practice { lastPractice = index }
                }
                if !placed { unscheduled += minutes }
            }
        }

        let result = sessions.sorted { ($0.day, $0.kind.order) < ($1.day, $1.kind.order) }
        return PlanResult(sessions: result, unscheduledMinutes: unscheduled, availableDays: days.count)
    }

    /// Learning time a topic still needs, from its size, understanding and importance.
    static func totalMinutes(for topic: PlanTopic) -> Int {
        let need = [1.0, 0.85, 0.65, 0.45, 0.25][max(0, min(4, topic.understanding))]
        let weight = [0.75, 1.0, 1.3][max(0, min(2, topic.importance))]
        let minutes = Double(max(topic.estimatedMinutes, 15)) * need * weight
        return Int((minutes / 5).rounded()) * 5
    }

    static func priority(_ topic: PlanTopic) -> Double {
        [0.75, 1.0, 1.3][max(0, min(2, topic.importance))] * Double(5 - max(0, min(4, topic.understanding)))
    }

    /// Splits a topic's minutes into learn / practise / review sessions.
    static func pieces(for topic: PlanTopic, total: Int) -> [(SessionKind, Int)] {
        let shares: [(SessionKind, Double)]
        switch topic.understanding {
        case ...1: shares = [(.learn, 0.5), (.practice, 0.35), (.review, 0.15)]
        case 2: shares = [(.learn, 0.25), (.practice, 0.5), (.review, 0.25)]
        case 3: shares = [(.practice, 0.5), (.review, 0.5)]
        default: shares = [(.review, 1)]
        }
        var result: [(SessionKind, Int)] = []
        for (kind, share) in shares {
            var remaining = Int((Double(total) * share / 5).rounded()) * 5
            guard remaining >= 10 else { continue }
            while remaining > 0 {
                var chunk = min(maxChunk, remaining)
                let rest = remaining - chunk
                // Never leave a remainder shorter than a useful session.
                if rest > 0 && rest < minChunk { chunk = remaining - minChunk }
                if chunk < minChunk { chunk = remaining }
                result.append((kind, chunk))
                remaining -= chunk
            }
        }
        return result
    }
}

private extension SessionKind {
    var order: Int {
        switch self {
        case .learn: 0
        case .practice: 1
        case .review: 2
        case .free: 3
        case .mockTest: 4
        case .finalReview: 5
        }
    }
}

// MARK: - Spaced repetition

enum ReviewGrade: Int, CaseIterable, Sendable {
    case again = 0, hard = 3, good = 4, easy = 5

    var title: String {
        switch self {
        case .again: "Nochmal"
        case .hard: "Schwer"
        case .good: "Gut"
        case .easy: "Leicht"
        }
    }
}

struct CardSchedule: Equatable, Sendable {
    var ease: Double = 2.5
    var intervalDays: Int = 0
    var repetitions: Int = 0
    var lapses: Int = 0
    var due: Date = .distantPast
}

/// SM-2 (the algorithm behind Anki and SuperMemo): cards you know come back
/// later and later, cards you don't know come back the same day.
enum SpacedRepetition {
    static func review(_ card: CardSchedule, grade: ReviewGrade, now: Date, calendar: Calendar = .school) -> CardSchedule {
        var next = card
        let q = Double(grade.rawValue)
        if grade == .again {
            next.repetitions = 0
            next.intervalDays = 0
            next.lapses += 1
            next.ease = max(1.3, card.ease - 0.2)
            next.due = now.addingTimeInterval(10 * 60)
            return next
        }
        next.repetitions += 1
        switch next.repetitions {
        case 1: next.intervalDays = grade == .easy ? 3 : 1
        case 2: next.intervalDays = grade == .easy ? 6 : (grade == .hard ? 2 : 4)
        default:
            let factor = grade == .hard ? 0.8 : (grade == .easy ? 1.3 : 1)
            next.intervalDays = max(card.intervalDays + 1, Int((Double(card.intervalDays) * card.ease * factor).rounded()))
        }
        next.ease = max(1.3, card.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)))
        next.due = calendar.addingDays(next.intervalDays, to: calendar.startOfDay(for: now))
        return next
    }
}

// MARK: - Exam readiness

enum TopicState: String, Sendable {
    case notStarted, learning, needsReview, confident

    var title: String {
        switch self {
        case .notStarted: "Nicht begonnen"
        case .learning: "In Arbeit"
        case .needsReview: "Wiederholen"
        case .confident: "Sicher"
        }
    }
}

struct ReadinessInput: Sendable {
    let id: UUID
    let importance: Int
    let understanding: Int
    let completion: Double
    let lastStudied: Date?
    /// Practice scores (0 … 1), newest first.
    let scores: [Double]
}

struct TopicReadiness: Equatable, Sendable {
    let id: UUID
    let score: Double
    let state: TopicState
    let reason: String
}

/// Exam readiness from understanding, practice results, finished material and
/// how long ago a topic was studied – not just from ticked-off tasks.
enum Readiness {
    static func evaluate(_ topics: [ReadinessInput], now: Date, calendar: Calendar = .school) -> (overall: Double, topics: [TopicReadiness]) {
        guard !topics.isEmpty else { return (0, []) }
        var weighted = 0.0, weights = 0.0
        var results: [TopicReadiness] = []

        for topic in topics {
            let understanding = Double(max(0, min(4, topic.understanding))) / 4
            let recent = Array(topic.scores.prefix(3))
            let practice = recent.isEmpty ? understanding * 0.6 : recent.reduce(0, +) / Double(recent.count)
            let daysAgo = topic.lastStudied.map { calendar.daysBetween($0, now) }
            let decay: Double = {
                guard let daysAgo, daysAgo > 5 else { return 1 }
                return max(0.7, 1 - Double(daysAgo - 5) / 80)
            }()
            let score = min(1, (0.55 * understanding + 0.25 * practice + 0.2 * topic.completion) * decay)

            let state: TopicState
            if topic.understanding == 0 && topic.completion == 0 && topic.lastStudied == nil && recent.isEmpty {
                state = .notStarted
            } else if topic.understanding >= 3 && ((daysAgo ?? 0) > 10 || (!recent.isEmpty && practice < 0.6)) {
                state = .needsReview
            } else if topic.understanding >= 4 && (recent.isEmpty || practice >= 0.8) {
                state = .confident
            } else {
                state = .learning
            }

            let reason: String
            if state == .notStarted {
                reason = "Noch nicht begonnen"
            } else if topic.completion >= 0.9 && topic.understanding <= 1 {
                reason = "Material fertig, aber noch nicht verstanden"
            } else if let last = recent.first, last < 0.6 {
                reason = "Letzte Übung \(Int((last * 100).rounded())) %"
            } else if let daysAgo, daysAgo > 10 {
                reason = "Seit \(daysAgo) Tagen nicht wiederholt"
            } else {
                reason = Understanding(rawValue: topic.understanding)?.title ?? ""
            }

            let weight = [0.75, 1.0, 1.3][max(0, min(2, topic.importance))]
            weighted += score * weight
            weights += weight
            results.append(TopicReadiness(id: topic.id, score: score, state: state, reason: reason))
        }
        return (weighted / max(weights, 0.0001), results)
    }
}

// MARK: - Flashcards from notes

enum NoteFlashcards {
    /// Lines like `Begriff :: Erklärung` (list markers allowed) become cards.
    static func extract(from body: String) -> [(front: String, back: String)] {
        body.components(separatedBy: "\n").compactMap { raw -> (front: String, back: String)? in
            let line = LineStyle.strip(raw.trimmingCharacters(in: .whitespaces))
            guard let range = line.range(of: "::") else { return nil }
            let front = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let back = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return (front, back)
        }
    }
}
