import SwiftData
import WidgetKit

/// Keeps the widgets' snapshot up to date after changes.
@MainActor
enum WidgetBridge {
    private static var pending: Task<Void, Never>?

    static func scheduleRefresh(context: ModelContext) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            refresh(context: context)
        }
    }

    static func refresh(context: ModelContext, now: Date = .now) {
        guard WidgetSnapshot.fileURL != nil else { return }
        let snapshot = makeSnapshot(context: context, now: now)
        if snapshot != WidgetSnapshot.load().map({ var old = $0; old.generatedAt = snapshot.generatedAt; return old }) {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func makeSnapshot(context: ModelContext, now: Date) -> WidgetSnapshot {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let calendar = Calendar.school
        let subjects = all(SchoolSubject.self)
        let exams = all(Exam.self)
        let tasks = all(SchoolTask.self)
        let agenda = Agenda(lessons: all(Lesson.self), exams: exams, tasks: tasks, events: all(CalendarEvent.self),
                            holidays: all(Holiday.self), sessions: all(StudySession.self), entries: all(TimetableEntry.self),
                            topics: all(Topic.self), subjects: subjects)

        var snapshot = WidgetSnapshot(generatedAt: now)
        for offset in 0..<4 {
            let day = calendar.addingDays(offset, to: calendar.startOfDay(for: now))
            for item in agenda.items(on: day) where item.isLesson && !item.isAllDay {
                let subject = DayPlan.subject(of: item, in: subjects)
                var room = ""
                switch item.source {
                case .lesson(let lesson): room = lesson.room.isEmpty ? (lesson.subject?.room ?? "") : lesson.room
                case .entry(let entry): room = entry.room
                default: break
                }
                snapshot.lessons.append(.init(start: item.start, end: item.end, subject: item.title, room: room,
                                              colorKey: subject?.colorKey ?? "gray", cancelled: item.isDone,
                                              changed: item.isChange, subjectID: subject?.uid))
            }
        }
        let horizon = calendar.addingDays(8, to: calendar.startOfDay(for: now))
        snapshot.tasks = tasks
            .filter { !$0.isDone && ($0.dueDate.map { $0 < horizon } ?? false) }
            .sorted(by: TasksView.byDue)
            .prefix(12)
            .map { .init(id: $0.uid, title: $0.title, subject: $0.subject?.name ?? "", colorKey: $0.subject?.colorKey ?? "gray", due: $0.dueDate) }
        snapshot.exams = exams
            .filter { $0.date >= calendar.startOfDay(for: now) && $0.date < calendar.addingDays(90, to: now) }
            .sorted { $0.date < $1.date }
            .prefix(6)
            .map { exam in
                .init(id: exam.uid, title: exam.displayTitle, subject: exam.subject?.name ?? "",
                      colorKey: exam.subject?.colorKey ?? "gray", date: exam.date,
                      readiness: LearningStore.readiness(for: exam, context: context, now: now).overall)
            }
        return snapshot
    }
}
