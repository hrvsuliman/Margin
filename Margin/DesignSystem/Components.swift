import SwiftData
import SwiftUI
import UIKit

// MARK: - Page styling

extension View {
    /// Inset-grouped list on paper. Used by every list screen.
    func marginList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
    }

    /// Row surface inside a `marginList()`.
    func marginRow() -> some View {
        listRowBackground(Palette.sheet)
    }
}

/// Serif section header, as on a page of notes.
struct SectionTitle: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

/// A calm message for screens or sections without content.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.faintInk)
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .foregroundStyle(Palette.paper)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }
}

struct SubjectDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A coloured vertical line like the margin of a notebook page.
struct MarginBar: View {
    let color: Color
    var width: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(color)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

// MARK: - Share sheet

/// The system share sheet (AirDrop, WhatsApp, Mail, "In Dateien sichern" …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Deleting safely

enum Deferred {
    /// Runs `work` once a closing sheet or popped screen has finished animating.
    /// Deleting a model while a visible screen still reads it can crash SwiftData,
    /// so screens dismiss first and delete afterwards.
    @MainActor
    static func afterDismiss(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            work()
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Task row

/// Round tick box for tasks.
struct CheckButton: View {
    let isOn: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? color : Palette.faintInk)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Erledigt" : "Offen")
        .accessibilityHint("Doppeltippen, um den Status zu ändern")
    }
}

enum TaskActions {
    @MainActor
    static func toggleDone(_ task: SchoolTask, context: ModelContext) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            task.status = task.isDone ? .open : .done
        }
        if task.isDone { Haptics.success() } else { Haptics.tap() }
        context.commit()
    }

    /// "überfällig", "heute", "morgen", "Fr., 6. Nov."
    static func dueText(_ task: SchoolTask, now: Date = .now) -> String? {
        guard let due = task.dueDate else { return nil }
        if task.isOverdue(now: now) { return "überfällig · \(Fmt.dayMonth(due))" }
        let days = Calendar.school.daysBetween(now, due)
        var text: String
        switch days {
        case 0: text = "heute"
        case 1: text = "morgen"
        case 2...6: text = Fmt.weekday(due)
        default: text = Fmt.shortDay(due)
        }
        if task.hasDueTime { text += " \(Fmt.time(due))" }
        return text
    }
}

struct TaskRow: View {
    @Environment(\.modelContext) private var context
    let task: SchoolTask
    var showSubject = true

    var body: some View {
        HStack(spacing: 10) {
            CheckButton(isOn: task.isDone, color: task.subject?.color.color ?? Palette.ink) {
                TaskActions.toggleDone(task, context: context)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(task.isDone ? Palette.secondaryInk : Palette.ink)
                    .strikethrough(task.isDone, color: Palette.secondaryInk)
                    .lineLimit(2)
                details
            }
            Spacer(minLength: 0)
            if task.priority == .high && !task.isDone {
                Image(systemName: "exclamationmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.marginRed)
                    .accessibilityLabel("Hohe Priorität")
            }
        }
        .padding(.vertical, 2)
    }

    private var details: some View {
        HStack(spacing: 6) {
            if showSubject, let subject = task.subject {
                SubjectDot(color: subject.color.color, size: 7)
                Text(subject.name)
            } else if showSubject {
                Text(task.kind.title)
            }
            if let due = TaskActions.dueText(task) {
                Text(due)
                    .foregroundStyle(task.isOverdue() ? Palette.marginRed : Palette.secondaryInk)
            }
            let subtasks = task.subtasks ?? []
            if !subtasks.isEmpty {
                Label("\(subtasks.filter(\.isDone).count)/\(subtasks.count)", systemImage: "checklist")
                    .labelStyle(.titleAndIcon)
            }
            if !(task.attachments ?? []).isEmpty {
                Image(systemName: "paperclip")
                    .accessibilityLabel("Mit Anhang")
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.secondaryInk)
        .lineLimit(1)
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ruling, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Agenda row

struct AgendaRow: View {
    let item: AgendaItem
    var now: Date = .now

    private var isPast: Bool {
        !item.isAllDay && item.end < now
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                if item.isAllDay {
                    Image(systemName: item.symbol)
                        .font(.footnote)
                        .foregroundStyle(item.color)
                } else {
                    Text(Fmt.time(item.start))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.ink)
                    Text(Fmt.time(item.end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(width: 46, alignment: .trailing)

            MarginBar(color: item.color)
                .frame(height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(item.isDone ? Palette.secondaryInk : Palette.ink)
                    .strikethrough(item.isDone, color: Palette.secondaryInk)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(isPast ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}
