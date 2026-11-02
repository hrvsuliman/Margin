import Foundation
import SwiftData

/// The actions Claude may take in Margin – used both by the in-app assistant
/// and by the local MCP server (Claude Code / Claude Desktop on the PC).
/// One definition, two front ends.
struct ToolSpec {
    let name: String
    let description: String
    let schema: [String: Any]
    /// Read-only tools never change data.
    let readOnly: Bool
    /// Short German label for the activity log, e.g. "Aufgabe anlegen".
    let label: String

    var apiDefinition: [String: Any] {
        ["name": name, "description": description, "input_schema": schema]
    }

    var mcpDefinition: [String: Any] {
        ["name": name, "description": description, "inputSchema": schema,
         "annotations": ["readOnlyHint": readOnly, "title": label]]
    }
}

struct ToolOutcome {
    let text: String
    let isError: Bool

    static func ok(_ value: Any) -> ToolOutcome { ToolOutcome(text: MarginTools.json(value), isError: false) }
    static func error(_ message: String) -> ToolOutcome { ToolOutcome(text: message, isError: true) }
}

@MainActor
enum MarginTools {
    // MARK: Schemas

    private static func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    private static let string: [String: Any] = ["type": "string"]
    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }

    static let specs: [ToolSpec] = [
        ToolSpec(name: "get_overview",
                 description: "Today's date, the user's subjects, upcoming exams with readiness, open and overdue task counts and the suggested next learning step. Call this first to get oriented.",
                 schema: object([:]), readOnly: true, label: "Überblick lesen"),
        ToolSpec(name: "list_tasks",
                 description: "List school tasks (homework, assignments, projects). Filter by status and subject.",
                 schema: object([
                    "status": ["type": "string", "enum": ["open", "overdue", "done", "all"], "description": "Default: open"],
                    "subject": string("Subject name, optional"),
                 ]), readOnly: true, label: "Aufgaben lesen"),
        ToolSpec(name: "list_exams",
                 description: "Upcoming exams with date, subject, readiness (0-100) and their topics with understanding levels (0 = not understood … 4 = can explain and apply).",
                 schema: object(["include_past": ["type": "boolean"]]), readOnly: true, label: "Prüfungen lesen"),
        ToolSpec(name: "get_timetable",
                 description: "The weekly timetable (lessons per weekday with times and rooms).",
                 schema: object([:]), readOnly: true, label: "Stundenplan lesen"),
        ToolSpec(name: "list_topics",
                 description: "Topics of a subject (with subtopics), their notes and the user's understanding level and last study date.",
                 schema: object(["subject": string("Subject name")], required: ["subject"]), readOnly: true, label: "Themen lesen"),
        ToolSpec(name: "list_notes",
                 description: "The user's notes (id, title, subject, date, first line). Optional full-text search.",
                 schema: object(["query": string("Search text, optional"), "subject": string("Subject name, optional")]),
                 readOnly: true, label: "Notizen suchen"),
        ToolSpec(name: "read_note",
                 description: "Full text of one note. Markup: '# ' heading, '## ' subheading, '- ' list, 'Begriff :: Erklärung' becomes a flashcard.",
                 schema: object(["id": string("Note id from list_notes")], required: ["id"]), readOnly: true, label: "Notiz lesen"),
        ToolSpec(name: "list_flashcards",
                 description: "Flashcards, optionally only those due for review or of one subject.",
                 schema: object(["subject": string("Subject name, optional"), "due_only": ["type": "boolean"]]),
                 readOnly: true, label: "Karteikarten lesen"),
        ToolSpec(name: "get_study_stats",
                 description: "Learning time, sessions, improved topics and reviewed cards for this week and the last 4 weeks.",
                 schema: object([:]), readOnly: true, label: "Statistik lesen"),

        ToolSpec(name: "add_task",
                 description: "Create a school task. Dates as YYYY-MM-DD.",
                 schema: object([
                    "title": string,
                    "subject": string("Subject name, optional"),
                    "due_date": string("YYYY-MM-DD, optional"),
                    "kind": ["type": "string", "enum": TaskKind.allCases.map(\.rawValue)],
                    "details": string("Optional notes"),
                 ], required: ["title"]), readOnly: false, label: "Aufgabe anlegen"),
        ToolSpec(name: "complete_task",
                 description: "Mark a task as done.",
                 schema: object(["id": string("Task id from list_tasks")], required: ["id"]), readOnly: false, label: "Aufgabe abhaken"),
        ToolSpec(name: "add_exam",
                 description: "Create an exam. Dates as YYYY-MM-DD.",
                 schema: object([
                    "subject": string("Subject name"),
                    "date": string("YYYY-MM-DD"),
                    "kind": ["type": "string", "enum": ExamKind.allCases.map(\.rawValue)],
                    "title": string("Optional, e.g. 'Funktionen'"),
                    "topics": ["type": "array", "items": string, "description": "Topic titles covered by the exam; created if missing"],
                 ], required: ["subject", "date"]), readOnly: false, label: "Prüfung anlegen"),
        ToolSpec(name: "add_topics",
                 description: "Add topics to a subject, optionally below a parent topic.",
                 schema: object([
                    "subject": string("Subject name"),
                    "titles": ["type": "array", "items": string],
                    "parent": string("Parent topic title, optional"),
                 ], required: ["subject", "titles"]), readOnly: false, label: "Themen anlegen"),
        ToolSpec(name: "set_understanding",
                 description: "Record how well the user understands a topic: 0 not yet, 1 barely, 2 basics, 3 mostly, 4 can explain and apply. Only after evidence from the conversation (answers, quiz).",
                 schema: object([
                    "subject": string("Subject name"),
                    "topic": string("Topic title"),
                    "level": ["type": "integer", "minimum": 0, "maximum": 4],
                 ], required: ["subject", "topic", "level"]), readOnly: false, label: "Verständnis eintragen"),
        ToolSpec(name: "log_practice_result",
                 description: "Store the score of a quiz or practice test the user just did (0.0 to 1.0).",
                 schema: object([
                    "subject": string("Subject name"),
                    "topic": string("Topic title, optional"),
                    "score": ["type": "number", "minimum": 0, "maximum": 1],
                 ], required: ["subject", "score"]), readOnly: false, label: "Übungsergebnis speichern"),
        ToolSpec(name: "add_flashcards",
                 description: "Create flashcards (front: term or question, back: explanation or answer).",
                 schema: object([
                    "subject": string("Subject name, optional"),
                    "topic": string("Topic title, optional"),
                    "cards": ["type": "array", "items": object(["front": string, "back": string], required: ["front", "back"])],
                 ], required: ["cards"]), readOnly: false, label: "Karteikarten anlegen"),
        ToolSpec(name: "create_note",
                 description: "Create a note; Margin shows it in the user's own handwriting. Use the markup: '# ' heading, '## ' subheading, '- ' list items, short paragraphs. Lines 'Begriff :: Erklärung' also become flashcards.",
                 schema: object([
                    "title": string,
                    "body": string("Note text with markup"),
                    "subject": string("Subject name, optional"),
                    "folder": string("Optional folder, e.g. 'Lernzettel'"),
                 ], required: ["title", "body"]), readOnly: false, label: "Notiz erstellen"),
        ToolSpec(name: "plan_exam",
                 description: "(Re)build the learning plan of an exam from its topics, the user's understanding and the days left.",
                 schema: object(["exam_id": string("Exam id from list_exams")], required: ["exam_id"]), readOnly: false, label: "Lernplan erstellen"),
    ]

    static func spec(named name: String) -> ToolSpec? {
        specs.first { $0.name == name }
    }

    // MARK: Calling

    static func call(_ name: String, input: [String: Any], context: ModelContext) -> ToolOutcome {
        switch name {
        case "get_overview": return overview(context)
        case "list_tasks": return listTasks(input, context)
        case "list_exams": return listExams(input, context)
        case "get_timetable": return timetable(context)
        case "list_topics": return listTopics(input, context)
        case "list_notes": return listNotes(input, context)
        case "read_note": return readNote(input, context)
        case "list_flashcards": return listCards(input, context)
        case "get_study_stats": return stats(context)
        case "add_task": return addTask(input, context)
        case "complete_task": return completeTask(input, context)
        case "add_exam": return addExam(input, context)
        case "add_topics": return addTopics(input, context)
        case "set_understanding": return setUnderstanding(input, context)
        case "log_practice_result": return logResult(input, context)
        case "add_flashcards": return addCards(input, context)
        case "create_note": return createNote(input, context)
        case "plan_exam": return planExam(input, context)
        default: return .error("Unbekanntes Werkzeug: \(name)")
        }
    }

    // MARK: Helpers

    nonisolated static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func day(_ date: Date) -> String {
        let parts = Calendar.school.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0) + " (\(Fmt.shortWeekday(date)))"
    }

    /// Accepts YYYY-MM-DD and DD.MM.YYYY.
    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let calendar = Calendar.school
        let iso = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        if iso.count == 3 { return calendar.date(from: DateComponents(year: iso[0], month: iso[1], day: iso[2])) }
        let german = text.split(separator: ".").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if german.count == 3 { return calendar.date(from: DateComponents(year: german[2], month: german[1], day: german[0])) }
        return nil
    }

    private static func subject(named name: String?, _ context: ModelContext) -> SchoolSubject? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let subjects = all(SchoolSubject.self, context)
        return subjects.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? subjects.first { $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name) }
            ?? subjects.first { $0.uid.uuidString == name }
    }

    private static func topic(named name: String?, in subject: SchoolSubject?) -> Topic? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, let subject else { return nil }
        let topics = subject.topics ?? []
        return topics.first { $0.title.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? topics.first { $0.title.localizedCaseInsensitiveContains(name) }
    }

    private static func subjectNames(_ context: ModelContext) -> String {
        all(SchoolSubject.self, context).map(\.name).joined(separator: ", ")
    }

    private static func missingSubject(_ name: String?, _ context: ModelContext) -> ToolOutcome {
        .error("Fach „\(name ?? "")“ nicht gefunden. Vorhandene Fächer: \(subjectNames(context))")
    }

    // MARK: Read

    private static func overview(_ context: ModelContext) -> ToolOutcome {
        let now = Date.now
        let today = Calendar.school.startOfDay(for: now)
        let tasks = all(SchoolTask.self, context)
        let exams = all(Exam.self, context).filter { $0.date >= today }.sorted { $0.date < $1.date }
        var result: [String: Any] = [
            "today": day(now),
            "subjects": all(SchoolSubject.self, context).sorted { $0.sortIndex < $1.sortIndex }.map(\.name),
            "open_tasks": tasks.filter { !$0.isDone }.count,
            "overdue_tasks": tasks.filter { $0.isOverdue(now: now) }.count,
            "due_flashcards": LearningStore.dueCards(context, now: now).count,
            "upcoming_exams": exams.prefix(6).map { exam in
                ["id": exam.uid.uuidString, "title": exam.displayTitle, "date": day(exam.date),
                 "readiness": Int((LearningStore.readiness(for: exam, context: context, now: now).overall * 100).rounded())]
            },
        ]
        if let step = LearningStore.nextStep(context, now: now) {
            result["next_step"] = "\(step.title) – \(step.detail)"
        }
        return .ok(result)
    }

    private static func listTasks(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        let status = input["status"] as? String ?? "open"
        let subject = subject(named: input["subject"] as? String, context)
        if input["subject"] != nil && subject == nil { return missingSubject(input["subject"] as? String, context) }
        let now = Date.now
        let tasks = all(SchoolTask.self, context).filter { task in
            if let subject, task.subject != subject { return false }
            switch status {
            case "done": return task.isDone
            case "overdue": return task.isOverdue(now: now)
            case "all": return true
            default: return !task.isDone
            }
        }.sorted(by: TasksView.byDue)
        return .ok(tasks.prefix(60).map { task in
            var entry: [String: Any] = ["id": task.uid.uuidString, "title": task.title, "kind": task.kind.rawValue,
                                        "status": task.status.rawValue]
            if let subject = task.subject { entry["subject"] = subject.name }
            if let due = task.dueDate { entry["due"] = day(due) }
            if task.isOverdue(now: now) { entry["overdue"] = true }
            if !task.details.isEmpty { entry["details"] = String(task.details.prefix(300)) }
            return entry
        })
    }

    private static func listExams(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        let today = Calendar.school.startOfDay(for: .now)
        let includePast = input["include_past"] as? Bool ?? false
        let progress = LearningStore.progressMap(context)
        let exams = all(Exam.self, context).filter { includePast || $0.date >= today }.sorted { $0.date < $1.date }
        return .ok(exams.map { exam in
            let readiness = LearningStore.readiness(for: exam, context: context)
            let plan = LearningStore.existingPlan(for: exam, context: context)
            let topics = plan.map { LearningStore.topics(of: $0, context: context) } ?? []
            return [
                "id": exam.uid.uuidString, "title": exam.displayTitle, "kind": exam.kind.rawValue, "date": day(exam.date),
                "subject": exam.subject?.name ?? "", "readiness": Int((readiness.overall * 100).rounded()),
                "has_plan": !LearningStore.sessions(for: exam, context: context).isEmpty,
                "topics": topics.map { topic -> [String: Any] in
                    let state = readiness.topics.first { $0.id == topic.uid }
                    return ["title": topic.title, "understanding": progress[topic.uid]?.understandingRaw ?? 0,
                            "state": state?.state.rawValue ?? "notStarted", "note": state?.reason ?? ""]
                },
            ] as [String: Any]
        })
    }

    private static func timetable(_ context: ModelContext) -> ToolOutcome {
        let lessons = all(Lesson.self, context).sorted { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }
        var days: [String: [String]] = [:]
        for lesson in lessons {
            let room = lesson.room.isEmpty ? (lesson.subject?.room ?? "") : lesson.room
            days[Fmt.weekdayName(lesson.weekday), default: []].append(
                "\(Fmt.clock(lesson.startMinute))–\(Fmt.clock(lesson.endMinute)) \(lesson.subject?.name ?? "")\(room.isEmpty ? "" : " (\(room))")"
            )
        }
        return .ok(days)
    }

    private static func listTopics(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let subject = subject(named: input["subject"] as? String, context) else {
            return missingSubject(input["subject"] as? String, context)
        }
        let progress = LearningStore.progressMap(context)
        func describe(_ topic: Topic) -> [String: Any] {
            var entry: [String: Any] = ["title": topic.title, "understanding": progress[topic.uid]?.understandingRaw ?? 0]
            if !topic.details.isEmpty { entry["notes"] = String(topic.details.prefix(600)) }
            if let last = progress[topic.uid]?.lastStudied { entry["last_studied"] = day(last) }
            let children = topic.sortedChildren
            if !children.isEmpty { entry["subtopics"] = children.map(describe) }
            return entry
        }
        return .ok(subject.rootTopics.map(describe))
    }

    private static func listNotes(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        let query = (input["query"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let subject = subject(named: input["subject"] as? String, context)
        let subjects = all(SchoolSubject.self, context)
        let notes = all(NoteDocument.self, context)
            .filter { subject == nil || $0.subjectUID == subject?.uid }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return .ok(notes.prefix(40).map { note in
            [
                "id": note.uid.uuidString, "title": note.title.isEmpty ? "Ohne Titel" : note.title, "date": day(note.noteDate),
                "subject": subjects.first { $0.uid == note.subjectUID }?.name ?? "",
                "first_line": String(note.body.split(separator: "\n").first ?? "").prefix(120).description,
            ] as [String: Any]
        })
    }

    private static func readNote(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let id = input["id"] as? String, let note = all(NoteDocument.self, context).first(where: { $0.uid.uuidString == id }) else {
            return .error("Notiz nicht gefunden. Nutze list_notes für gültige ids.")
        }
        return .ok(["title": note.title, "date": day(note.noteDate), "body": note.body])
    }

    private static func listCards(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        let subject = subject(named: input["subject"] as? String, context)
        let dueOnly = input["due_only"] as? Bool ?? false
        let now = Date.now
        let cards = all(Flashcard.self, context)
            .filter { subject == nil || $0.subjectUID == subject?.uid }
            .filter { !dueOnly || $0.due <= now }
        let names = Dictionary(all(SchoolSubject.self, context).map { ($0.uid, $0.name) }, uniquingKeysWith: { a, _ in a })
        return .ok(cards.prefix(150).map { card -> [String: Any] in
            ["front": card.front, "back": card.back, "due": card.due <= now,
             "subject": card.subjectUID.flatMap { names[$0] } ?? ""]
        })
    }

    private static func stats(_ context: ModelContext) -> ToolOutcome {
        let week = LearningStore.week(containing: .now, context: context)
        let subjects = all(SchoolSubject.self, context)
        var bySubject: [String: Int] = [:]
        for (id, minutes) in week.bySubject {
            bySubject[subjects.first { $0.uid == id }?.name ?? "Ohne Fach"] = minutes
        }
        let results = all(PracticeResult.self, context).sorted { $0.date > $1.date }.prefix(10)
        return .ok([
            "this_week_minutes": week.minutes, "this_week_sessions": week.sessions,
            "improved_topics_this_week": week.improvedTopics, "cards_reviewed_this_week": week.cardsReviewed,
            "minutes_by_subject_this_week": bySubject,
            "recent_practice_scores": results.map { ["date": day($0.date), "score": $0.score, "kind": $0.kind] as [String: Any] },
        ])
    }

    // MARK: Write

    private static func addTask(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            return .error("Titel fehlt.")
        }
        let subject = subject(named: input["subject"] as? String, context)
        let task = SchoolTask(title: title, kind: TaskKind(rawValue: input["kind"] as? String ?? "") ?? .homework)
        context.insert(task)
        task.subject = subject
        task.dueDate = parseDate(input["due_date"] as? String)
        task.details = input["details"] as? String ?? ""
        context.commit()
        return .ok(["created_task_id": task.uid.uuidString, "subject": subject?.name ?? "kein Fach",
                    "due": task.dueDate.map(day) ?? "kein Datum"])
    }

    private static func completeTask(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let id = input["id"] as? String, let task = all(SchoolTask.self, context).first(where: { $0.uid.uuidString == id }) else {
            return .error("Aufgabe nicht gefunden. Nutze list_tasks für gültige ids.")
        }
        task.status = .done
        context.commit()
        return .ok(["done": task.title])
    }

    private static func addExam(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let subject = subject(named: input["subject"] as? String, context) else {
            return missingSubject(input["subject"] as? String, context)
        }
        guard let date = parseDate(input["date"] as? String) else { return .error("Datum fehlt oder ist ungültig (YYYY-MM-DD).") }
        let kind = ExamKind(rawValue: input["kind"] as? String ?? "") ?? AppSettings.shared.schoolType.defaultExamKind
        let exam = Exam(title: input["title"] as? String ?? "", kind: kind, date: date, subject: nil)
        context.insert(exam)
        exam.subject = subject
        let titles = input["topics"] as? [String] ?? []
        if !titles.isEmpty {
            let plan = LearningStore.plan(for: exam, context: context)
            plan.topicUIDs = titles.map { ensureTopic($0, in: subject, parent: nil, context: context).uid }
        }
        context.commit()
        return .ok(["created_exam_id": exam.uid.uuidString, "title": exam.displayTitle, "date": day(date), "topics": titles])
    }

    @discardableResult
    private static func ensureTopic(_ title: String, in subject: SchoolSubject, parent: Topic?, context: ModelContext) -> Topic {
        if let existing = topic(named: title, in: subject), existing.title.compare(title, options: .caseInsensitive) == .orderedSame {
            return existing
        }
        let created = Topic(title: title, subject: nil, sortIndex: (parent?.children?.count ?? subject.rootTopics.count))
        context.insert(created)
        created.subject = subject
        created.parent = parent
        return created
    }

    private static func addTopics(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let subject = subject(named: input["subject"] as? String, context) else {
            return missingSubject(input["subject"] as? String, context)
        }
        let parent = topic(named: input["parent"] as? String, in: subject)
        let titles = (input["titles"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let created = titles.map { ensureTopic($0, in: subject, parent: parent, context: context).title }
        context.commit()
        return .ok(["subject": subject.name, "topics": created, "parent": parent?.title ?? ""])
    }

    private static func setUnderstanding(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let subject = subject(named: input["subject"] as? String, context) else {
            return missingSubject(input["subject"] as? String, context)
        }
        guard let topic = topic(named: input["topic"] as? String, in: subject) else {
            return .error("Thema „\(input["topic"] as? String ?? "")“ nicht gefunden in \(subject.name).")
        }
        let level = Understanding(rawValue: (input["level"] as? Int) ?? Int((input["level"] as? Double) ?? 0)) ?? .notYet
        LearningStore.setUnderstanding(level, topicUID: topic.uid, source: "assistant", context: context)
        return .ok(["topic": topic.title, "understanding": level.rawValue, "label": level.title])
    }

    private static func logResult(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let subject = subject(named: input["subject"] as? String, context) else {
            return missingSubject(input["subject"] as? String, context)
        }
        let score = min(max((input["score"] as? Double) ?? Double(input["score"] as? Int ?? 0), 0), 1)
        let topic = topic(named: input["topic"] as? String, in: subject)
        let result = PracticeResult(score: score, kind: "quiz")
        result.subjectUID = subject.uid
        result.topicUID = topic?.uid
        context.insert(result)
        LearningStore.markStudied(topicUID: topic?.uid, context: context)
        try? context.save()
        return .ok(["saved_score": score, "topic": topic?.title ?? ""])
    }

    private static func addCards(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        let subject = subject(named: input["subject"] as? String, context)
        let topic = topic(named: input["topic"] as? String, in: subject)
        let cards = (input["cards"] as? [[String: Any]] ?? []).compactMap { entry -> (String, String)? in
            guard let front = entry["front"] as? String, let back = entry["back"] as? String,
                  !front.isEmpty, !back.isEmpty else { return nil }
            return (front, back)
        }
        guard !cards.isEmpty else { return .error("Keine gültigen Karten (front und back nötig).") }
        for (front, back) in cards {
            let card = Flashcard(front: front, back: back)
            card.subjectUID = subject?.uid
            card.topicUID = topic?.uid
            context.insert(card)
        }
        try? context.save()
        return .ok(["created_cards": cards.count, "subject": subject?.name ?? "", "topic": topic?.title ?? ""])
    }

    private static func createNote(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let title = input["title"] as? String, let body = input["body"] as? String, !body.isEmpty else {
            return .error("Titel und Text fehlen.")
        }
        let subject = subject(named: input["subject"] as? String, context)
        let note = NoteDocument(title: title)
        note.body = body
        note.subjectUID = subject?.uid
        note.folder = input["folder"] as? String ?? ""
        context.insert(note)
        try? context.save()
        LearningStore.syncCards(for: note, context: context)
        return .ok(["created_note_id": note.uid.uuidString, "title": title,
                    "flashcards_from_note": NoteFlashcards.extract(from: body).count])
    }

    private static func planExam(_ input: [String: Any], _ context: ModelContext) -> ToolOutcome {
        guard let id = input["exam_id"] as? String, let exam = all(Exam.self, context).first(where: { $0.uid.uuidString == id }) else {
            return .error("Prüfung nicht gefunden. Nutze list_exams für gültige ids.")
        }
        let result = LearningStore.regenerate(exam: exam, context: context)
        ReminderService.scheduleRefresh(context: context)
        return .ok(["sessions": result.sessions.count, "days": result.availableDays,
                    "unscheduled_minutes": result.unscheduledMinutes])
    }
}
