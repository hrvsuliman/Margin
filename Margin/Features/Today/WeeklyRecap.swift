import SwiftData
import SwiftUI

/// What happened this week and what's coming next. Neutral numbers, no streaks, no pressure.
struct WeeklyRecap {
    var weekStart: Date
    var minutes = 0
    var sessions = 0
    var improvedTopics = 0
    var cardsReviewed = 0
    var tasksDone = 0
    var notesWritten = 0
    /// Minutes per subject name, largest first.
    var topSubjects: [(name: String, minutes: Int, color: Color)] = []
    var examsNext: [(title: String, date: Date)] = []
    var tasksNext = 0

    var isEmpty: Bool { minutes == 0 && tasksDone == 0 && notesWritten == 0 && cardsReviewed == 0 }

    /// Friday afternoon to Sunday, when looking back makes sense.
    static func isRecapTime(_ now: Date) -> Bool {
        let calendar = Calendar.school
        let weekday = calendar.component(.weekday, from: now)
        return weekday == 1 || weekday == 7 || (weekday == 6 && calendar.component(.hour, from: now) >= 14)
    }

    @MainActor
    static func make(for date: Date, context: ModelContext) -> WeeklyRecap {
        let calendar = Calendar.school
        let start = calendar.startOfWeek(for: date)
        let end = calendar.addingDays(7, to: start)
        let week = LearningStore.week(containing: date, context: context)
        let subjects = (try? context.fetch(FetchDescriptor<SchoolSubject>())) ?? []

        var recap = WeeklyRecap(weekStart: start)
        recap.minutes = week.minutes
        recap.sessions = week.sessions
        recap.improvedTopics = week.improvedTopics
        recap.cardsReviewed = week.cardsReviewed
        recap.topSubjects = week.bySubject
            .compactMap { id, minutes in
                subjects.first { $0.uid == id }.map { (name: $0.name, minutes: minutes, color: $0.color.color) }
            }
            .sorted { $0.minutes > $1.minutes }
            .prefix(4)
            .map { $0 }
        let tasks = (try? context.fetch(FetchDescriptor<SchoolTask>())) ?? []
        recap.tasksDone = tasks.filter { task in task.completedAt.map { $0 >= start && $0 < end } ?? false }.count
        recap.tasksNext = tasks.filter { task in
            !task.isDone && task.dueDate.map { $0 >= end && $0 < calendar.addingDays(7, to: end) } == true
        }.count
        recap.notesWritten = ((try? context.fetch(FetchDescriptor<NoteDocument>())) ?? [])
            .filter { $0.createdAt >= start && $0.createdAt < end }.count
        recap.examsNext = ((try? context.fetch(FetchDescriptor<Exam>())) ?? [])
            .filter { $0.date >= end && $0.date < calendar.addingDays(7, to: end) }
            .sorted { $0.date < $1.date }
            .map { (title: [$0.subject?.name, $0.displayTitle].compactMap { $0 }.joined(separator: " · "), date: $0.date) }
        return recap
    }
}

/// The small card on the Today screen.
struct WeeklyRecapCard: View {
    let recap: WeeklyRecap

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Palette.marginRed)
            VStack(alignment: .leading, spacing: 3) {
                Text("Deine Woche")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var line: String {
        var parts: [String] = []
        if recap.minutes > 0 { parts.append("\(recap.minutes) Min. gelernt") }
        if recap.tasksDone > 0 { parts.append("\(recap.tasksDone) Aufgaben erledigt") }
        if !recap.examsNext.isEmpty { parts.append("\(recap.examsNext.count) Prüfung\(recap.examsNext.count == 1 ? "" : "en") nächste Woche") }
        return parts.isEmpty ? "Rückblick und Vorschau" : parts.joined(separator: " · ")
    }
}

/// The full recap, also shareable as an image.
struct WeeklyRecapView: View {
    @Environment(\.dismiss) private var dismiss
    let recap: WeeklyRecap
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                RecapSheet(recap: recap)
                    .padding(16)
            }
            .background(Palette.paper)
            .navigationTitle("Wochenrückblick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let image {
                        ShareLink(item: image, preview: SharePreview("Meine Woche", image: image)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .tint(Palette.marginRed)
        .onAppear(perform: renderImage)
    }

    @MainActor
    private func renderImage() {
        // Always light for the shared picture, whatever the phone's appearance.
        let renderer = ImageRenderer(content: RecapSheet(recap: recap)
            .padding(24)
            .frame(width: 390)
            .background(Color(white: 0.98))
            .environment(\.colorScheme, .light))
        renderer.scale = 3
        if let uiImage = renderer.uiImage { image = Image(uiImage: uiImage) }
    }
}

/// The recap layout itself (used on screen and for the shared image).
private struct RecapSheet: View {
    let recap: WeeklyRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Woche vom \(Fmt.dayMonth(recap.weekStart))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                Text(recap.isEmpty ? "Eine ruhige Woche" : "Das hast du geschafft")
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tile("\(recap.minutes)", "Minuten gelernt", "timer")
                tile("\(recap.tasksDone)", "Aufgaben erledigt", "checkmark.circle")
                tile("\(recap.improvedTopics)", "Themen verbessert", "arrow.up.right")
                tile("\(recap.cardsReviewed)", "Karten wiederholt", "rectangle.on.rectangle.angled")
                if recap.notesWritten > 0 {
                    tile("\(recap.notesWritten)", "Notizen geschrieben", "pencil.and.outline")
                }
                if recap.sessions > 0 {
                    tile("\(recap.sessions)", "Lerneinheiten", "list.bullet.clipboard")
                }
            }

            if !recap.topSubjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wofür du gelernt hast").font(.headline).foregroundStyle(Palette.ink)
                    let maximum = max(recap.topSubjects.map(\.minutes).max() ?? 1, 1)
                    ForEach(recap.topSubjects, id: \.name) { entry in
                        HStack(spacing: 10) {
                            Text(entry.name)
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink)
                                .frame(width: 110, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(entry.color)
                                    .frame(width: max(6, proxy.size.width * CGFloat(entry.minutes) / CGFloat(maximum)))
                            }
                            .frame(height: 8)
                            Text("\(entry.minutes) Min.")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Nächste Woche").font(.headline).foregroundStyle(Palette.ink)
                if recap.examsNext.isEmpty && recap.tasksNext == 0 {
                    Text("Keine Prüfungen und keine fälligen Aufgaben eingetragen.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(recap.examsNext, id: \.title) { exam in
                    Label("\(exam.title) · \(Fmt.weekday(exam.date)) \(Fmt.dayMonth(exam.date))", systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Palette.marginRed)
                }
                if recap.tasksNext > 0 {
                    Label("\(recap.tasksNext) Aufgabe\(recap.tasksNext == 1 ? "" : "n") fällig", systemImage: "checklist")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                }
            }

            Text("Margin")
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(Palette.faintInk)
        }
    }

    private func tile(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Palette.marginRed)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 12))
    }
}
