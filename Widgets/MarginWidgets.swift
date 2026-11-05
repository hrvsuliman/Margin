import SwiftUI
import WidgetKit

@main
struct MarginWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
        DueWidget()
        ExamCountdownWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// Nil when the app hasn't shared data yet (or the App Group isn't available).
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date.now
        let dates = [now] + (snapshot?.refreshDates(after: now) ?? [])
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        // Redraw at every lesson boundary, and at the latest every 30 minutes.
        let next = min(dates.dropFirst().first ?? now.addingTimeInterval(1800), now.addingTimeInterval(1800))
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let now = Date.now
        var snapshot = WidgetSnapshot()
        snapshot.lessons = [
            .init(start: now.addingTimeInterval(600), end: now.addingTimeInterval(3300), subject: "Mathematik", room: "204",
                  colorKey: "blue", cancelled: false, changed: false, subjectID: nil),
            .init(start: now.addingTimeInterval(3600), end: now.addingTimeInterval(6300), subject: "Biologie", room: "B12",
                  colorKey: "green", cancelled: false, changed: false, subjectID: nil),
        ]
        snapshot.tasks = [.init(id: UUID(), title: "S. 34 Nr. 5", subject: "Mathematik", colorKey: "blue", due: now)]
        snapshot.exams = [.init(id: UUID(), title: "Klassenarbeit", subject: "Biologie", colorKey: "green",
                                date: now.addingTimeInterval(4 * 86400), readiness: 0.6)]
        return snapshot
    }
}

private func color(_ key: String) -> Color {
    (SubjectColor(rawValue: key) ?? .gray).color
}

private struct EmptyWidget: View {
    var text = "Öffne Margin einmal, dann erscheint hier dein Tag."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Margin")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Palette.marginRed)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Next lesson

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "next-lesson", provider: SnapshotProvider()) { entry in
            NextLessonView(entry: entry)
                .containerBackground(Palette.paper, for: .widget)
                .widgetURL(URL(string: "margin://today"))
        }
        .configurationDisplayName("Nächste Stunde")
        .description("Was jetzt läuft und was als Nächstes kommt, mit Raum.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct NextLessonView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let lesson = snapshot.currentOrNextLesson(at: entry.date) {
            let isNow = lesson.start <= entry.date
            switch family {
            case .accessoryInline:
                Text("\(lesson.subject) \(lesson.start, style: .time)\(lesson.room.isEmpty ? "" : " · \(lesson.room)")")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(isNow ? "Jetzt" : "Als Nächstes").font(.caption2).widgetAccentable()
                    Text(lesson.subject).font(.headline).lineLimit(1)
                    Text("\(lesson.start, style: .time)\(lesson.room.isEmpty ? "" : " · Raum \(lesson.room)")")
                        .font(.caption)
                }
            default:
                HStack(alignment: .top, spacing: 12) {
                    lessonBlock(lesson, isNow: isNow)
                    if family == .systemMedium {
                        let later = snapshot.laterLessons(after: lesson).prefix(3)
                        if !later.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(later.enumerated()), id: \.offset) { _, next in
                                    HStack(spacing: 6) {
                                        Capsule().fill(color(next.colorKey)).frame(width: 3, height: 14)
                                        Text(next.start, style: .time)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Palette.secondaryInk)
                                        Text(next.subject)
                                            .font(.caption)
                                            .foregroundStyle(next.cancelled ? Palette.faintInk : Palette.ink)
                                            .strikethrough(next.cancelled)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        } else if entry.snapshot == nil {
            EmptyWidget()
        } else {
            EmptyWidget(text: "Heute und in den nächsten Tagen keine Stunden mehr.")
        }
    }

    private func lessonBlock(_ lesson: WidgetSnapshot.Lesson, isNow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isNow ? "JETZT" : "ALS NÄCHSTES")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color(lesson.colorKey))
            Text(lesson.subject)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            if !lesson.room.isEmpty {
                Text("Raum \(lesson.room)")
                    .font(.caption)
                    .foregroundStyle(lesson.changed ? Palette.marginRed : Palette.secondaryInk)
            }
            Spacer(minLength: 0)
            Text(isNow ? lesson.end : lesson.start, style: .relative)
                .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
            Text(isNow ? "bis Stundenende" : "bis Beginn")
                .font(.caption2)
                .foregroundStyle(Palette.faintInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Due

struct DueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "due", provider: SnapshotProvider()) { entry in
            DueView(entry: entry)
                .containerBackground(Palette.paper, for: .widget)
        }
        .configurationDisplayName("Fällig")
        .description("Hausaufgaben und Aufgaben der nächsten Tage.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct DueView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let tasks = snapshot.openTasks(at: entry.date)
            let shown = tasks.prefix(family == .systemMedium ? 4 : family == .accessoryRectangular ? 2 : 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Fällig")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Palette.marginRed)
                        .widgetAccentable()
                    Spacer()
                    if family != .accessoryRectangular {
                        Text("\(tasks.count)")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                }
                if tasks.isEmpty {
                    Text("Nichts offen.").font(.caption).foregroundStyle(Palette.secondaryInk)
                }
                ForEach(Array(shown), id: \.id) { task in
                    Link(destination: URL(string: "margin://task/\(task.id.uuidString)")!) {
                        HStack(spacing: 6) {
                            Capsule().fill(color(task.colorKey)).frame(width: 3, height: 13)
                            Text(task.title)
                                .font(.caption)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let due = task.due, family == .systemMedium {
                                Text(dueText(due))
                                    .font(.caption2)
                                    .foregroundStyle(due < Calendar.current.startOfDay(for: entry.date) ? Palette.marginRed : Palette.secondaryInk)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(URL(string: "margin://today"))
        } else {
            EmptyWidget()
        }
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "heute" }
        if calendar.isDateInTomorrow(date) { return "morgen" }
        if date < calendar.startOfDay(for: entry.date) { return "überfällig" }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE")))
    }
}

// MARK: - Exam countdown

struct ExamCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "exam", provider: SnapshotProvider()) { entry in
            ExamView(entry: entry)
                .containerBackground(Palette.paper, for: .widget)
        }
        .configurationDisplayName("Nächste Prüfung")
        .description("Tage bis zur nächsten Arbeit und wie gut du vorbereitet bist.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

private struct ExamView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let exam = entry.snapshot?.nextExam(at: entry.date) {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date),
                                                       to: Calendar.current.startOfDay(for: exam.date)).day ?? 0
            let daysText = days == 0 ? "heute" : days == 1 ? "morgen" : "in \(days) Tagen"
            Group {
                switch family {
                case .accessoryInline:
                    Text("\(exam.subject) \(daysText)")
                case .accessoryCircular:
                    Gauge(value: exam.readiness) {
                        Text(exam.subject.prefix(3))
                    } currentValueLabel: {
                        Text("\(days)")
                    }
                    .gaugeStyle(.accessoryCircular)
                default:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exam.subject.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color(exam.colorKey))
                            .lineLimit(1)
                        Text(exam.title)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        HStack(alignment: .lastTextBaseline) {
                            Text(days <= 1 ? daysText : "\(days)")
                                .font(.system(days <= 1 ? .title2 : .largeTitle, design: .rounded, weight: .semibold))
                                .foregroundStyle(days <= 3 ? Palette.marginRed : Palette.ink)
                            if days > 1 {
                                Text("Tage").font(.caption).foregroundStyle(Palette.secondaryInk)
                            }
                            Spacer()
                            Gauge(value: exam.readiness) { EmptyView() }
                                .gaugeStyle(.accessoryCircularCapacity)
                                .tint(color(exam.colorKey))
                                .scaleEffect(0.6)
                                .frame(width: 34, height: 34)
                        }
                    }
                }
            }
            .widgetURL(URL(string: "margin://exam/\(exam.id.uuidString)"))
        } else if entry.snapshot == nil {
            EmptyWidget()
        } else {
            EmptyWidget(text: "Keine Prüfung eingetragen.")
        }
    }
}
