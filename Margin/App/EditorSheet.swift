import SwiftUI

/// Every editor or detail screen that can open as a sheet from anywhere
/// (Today, Calendar, subject pages). Keeps presentation logic in one place.
enum EditorSheet: Identifiable {
    case newTask(subject: SchoolSubject?, dueDate: Date?, exam: Exam?, topic: Topic?)
    case task(SchoolTask)
    case newExam(subject: SchoolSubject?, date: Date?)
    case exam(Exam)
    case newEvent(date: Date?)
    case event(CalendarEvent)
    case newLesson(subject: SchoolSubject?, weekday: Int?, period: Int?)
    case lesson(Lesson)
    case newSubject
    case subject(SchoolSubject)
    case subjectTemplates
    case holiday(Holiday?)

    // Stable ids: an id that changed on every access would make the sheet flicker.
    var id: String {
        switch self {
        case .newTask: "new-task"
        case .task(let task): "task-\(task.uid)"
        case .newExam: "new-exam"
        case .exam(let exam): "exam-\(exam.uid)"
        case .newEvent: "new-event"
        case .event(let event): "event-\(event.uid)"
        case .newLesson: "new-lesson"
        case .lesson(let lesson): "lesson-\(lesson.uid)"
        case .newSubject: "new-subject"
        case .subject(let subject): "subject-\(subject.uid)"
        case .subjectTemplates: "subject-templates"
        case .holiday(let holiday): "holiday-\(holiday?.uid.uuidString ?? "new")"
        }
    }

    static func open(_ source: AgendaSource) -> EditorSheet {
        switch source {
        case .lesson(let lesson): .lesson(lesson)
        case .exam(let exam): .exam(exam)
        case .task(let task): .task(task)
        case .event(let event): .event(event)
        case .holiday(let holiday): .holiday(holiday)
        }
    }
}

/// The content shown for an `EditorSheet`.
struct EditorSheetView: View {
    let sheet: EditorSheet

    var body: some View {
        NavigationStack {
            content
        }
        .tint(Palette.marginRed)
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case let .newTask(subject, dueDate, exam, topic):
            TaskEditor(subject: subject, dueDate: dueDate, exam: exam, topic: topic)
        case .task(let task):
            TaskDetailView(task: task, showsDoneButton: true)
        case let .newExam(subject, date):
            ExamEditor(subject: subject, date: date)
        case .exam(let exam):
            ExamEditor(exam: exam)
        case .newEvent(let date):
            EventEditor(date: date)
        case .event(let event):
            EventEditor(event: event)
        case let .newLesson(subject, weekday, period):
            LessonEditor(subject: subject, weekday: weekday, period: period)
        case .lesson(let lesson):
            LessonEditor(lesson: lesson)
        case .newSubject:
            SubjectEditor(subject: nil)
        case .subject(let subject):
            SubjectEditor(subject: subject)
        case .subjectTemplates:
            SubjectTemplatesView()
        case .holiday(let holiday):
            HolidayEditor(holiday: holiday)
        }
    }
}

extension View {
    func editorSheet(_ sheet: Binding<EditorSheet?>) -> some View {
        self.sheet(item: sheet) { EditorSheetView(sheet: $0) }
    }
}
