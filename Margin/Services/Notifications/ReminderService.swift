import Foundation
import SwiftData
import UserNotifications

/// Local notifications for tasks, exams and events.
///
/// iOS keeps at most 64 pending notifications per app, so instead of scheduling
/// one per item forever, all reminders are rebuilt from the data after every
/// change and when the app opens: the next 60 within the coming 6 weeks.
@MainActor
enum ReminderService {
    static let center = UNUserNotificationCenter.current()
    private static var pendingRefresh: Task<Void, Never>?
    /// Turned off by unit tests, so they never touch real notifications.
    static var isEnabled = true

    /// Debounced refresh, so a burst of edits only reschedules once.
    static func scheduleRefresh(context: ModelContext) {
        guard isEnabled else { return }
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await refresh(context: context)
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func refresh(context: ModelContext, settings: AppSettings = .shared, now: Date = .now) async {
        guard isEnabled else { return }
        let planned = plannedReminders(context: context, settings: settings, now: now)

        var status = await authorizationStatus()
        if status == .notDetermined && !planned.isEmpty {
            await requestPermission()
            status = await authorizationStatus()
        }

        center.removeAllPendingNotificationRequests()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let parts = Calendar.school.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    struct Planned: Equatable {
        var id: String
        var date: Date
        var title: String
        var body: String
    }

    /// All reminders that should be pending right now, soonest first.
    static func plannedReminders(context: ModelContext, settings: AppSettings, now: Date) -> [Planned] {
        let calendar = Calendar.school
        let horizon = calendar.addingDays(42, to: now)
        var result: [Planned] = []

        func add(_ id: String, _ date: Date, _ title: String, _ body: String) {
            if date > now && date <= horizon {
                result.append(Planned(id: id, date: date, title: title, body: body))
            }
        }

        let tasks = (try? context.fetch(FetchDescriptor<SchoolTask>())) ?? []
        for task in tasks where !task.isDone {
            let subject = task.subject?.name ?? task.kind.title
            if let reminder = task.reminderDate {
                let due = task.dueDate.map { " · fällig \(Fmt.relativeDay($0, from: reminder))" } ?? ""
                add("task-\(task.uid)", reminder, task.title, subject + due)
            } else if let due = task.dueDate {
                let day = calendar.startOfDay(for: due)
                switch settings.defaultTaskReminder {
                case .off:
                    break
                case .eveningBefore:
                    add("task-\(task.uid)", calendar.date(on: calendar.addingDays(-1, to: day), minute: 17 * 60),
                        "Morgen fällig: \(task.title)", subject)
                case .morningOf:
                    add("task-\(task.uid)", calendar.date(on: day, minute: 7 * 60),
                        "Heute fällig: \(task.title)", subject)
                }
            }
        }

        let exams = (try? context.fetch(FetchDescriptor<Exam>())) ?? []
        for exam in exams where exam.reminderDaysBefore >= 0 {
            let day = calendar.startOfDay(for: exam.date)
            let fire = calendar.date(on: calendar.addingDays(-exam.reminderDaysBefore, to: day), minute: 17 * 60)
            let when = exam.reminderDaysBefore == 0 ? "heute" : Fmt.relativeDay(exam.date, from: fire)
            add("exam-\(exam.uid)", fire, "\(exam.displayTitle) \(when)", Fmt.longDay(exam.date))
        }

        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        let window = DateInterval(start: now, end: horizon)
        for event in events where event.reminderMinutesBefore >= 0 {
            for occurrence in CalendarMath.occurrences(of: event, in: window, calendar: calendar) {
                let fire = occurrence.start.addingTimeInterval(-Double(event.reminderMinutesBefore) * 60)
                let body = event.isAllDay ? Fmt.longDay(occurrence.start)
                    : "\(Fmt.shortDay(occurrence.start)), \(Fmt.time(occurrence.start))"
                add("event-\(event.uid)-\(Int(occurrence.start.timeIntervalSince1970))", fire, event.title, body)
            }
        }

        return Array(result.sorted { $0.date < $1.date }.prefix(60))
    }
}

/// Shows reminders as banners even while Margin is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
