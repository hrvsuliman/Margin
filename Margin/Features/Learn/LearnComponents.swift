import SwiftData
import SwiftUI

/// Colour of an understanding level, from warm (new) to calm green (confident).
extension Understanding {
    var color: Color {
        switch self {
        case .notYet: Palette.faintInk
        case .barely: SubjectColor.coral.color
        case .basics: SubjectColor.mustard.color
        case .mostly: SubjectColor.teal.color
        case .confident: SubjectColor.green.color
        }
    }
}

extension TopicState {
    var color: Color {
        switch self {
        case .notStarted: Palette.faintInk
        case .learning: SubjectColor.mustard.color
        case .needsReview: SubjectColor.coral.color
        case .confident: SubjectColor.green.color
        }
    }
}

/// Exam readiness as a ring with the percentage inside.
struct ReadinessRing: View {
    let value: Double
    var size: CGFloat = 54
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ruling, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
            Text("\(Int((value * 100).rounded()))")
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vorbereitet zu \(Int((value * 100).rounded())) Prozent")
    }

    private var color: Color {
        switch value {
        case ..<0.35: SubjectColor.coral.color
        case ..<0.7: SubjectColor.mustard.color
        default: SubjectColor.green.color
        }
    }
}

/// Five dots for the understanding level; tap a dot to set it.
struct UnderstandingDots: View {
    let level: Understanding
    var onChange: ((Understanding) -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Understanding.allCases.dropFirst()) { step in
                Circle()
                    .fill(step.rawValue <= level.rawValue ? level.color : Palette.ruling)
                    .frame(width: 9, height: 9)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture {
                        guard let onChange else { return }
                        onChange(level == step ? Understanding(rawValue: step.rawValue - 1) ?? .notYet : step)
                        Haptics.selection()
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verständnis: \(level.title)")
        .accessibilityAdjustableAction { direction in
            guard let onChange else { return }
            switch direction {
            case .increment: onChange(Understanding(rawValue: min(4, level.rawValue + 1)) ?? level)
            case .decrement: onChange(Understanding(rawValue: max(0, level.rawValue - 1)) ?? level)
            @unknown default: break
            }
        }
    }
}

/// Full list of the five levels with explanations, for pickers.
struct UnderstandingPicker: View {
    @Binding var level: Understanding

    var body: some View {
        ForEach(Understanding.allCases) { option in
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { level = option }
                Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    UnderstandingDots(level: option)
                    Text(option.title).foregroundStyle(Palette.ink)
                    Spacer()
                    if option == level {
                        Image(systemName: "checkmark").foregroundStyle(Palette.marginRed)
                    }
                }
            }
        }
    }
}

/// The big "do this now" card.
struct NextStepCard: View {
    let step: NextStep
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            HStack(spacing: 14) {
                Image(systemName: step.symbol)
                    .font(.title2)
                    .foregroundStyle(Palette.marginRed)
                    .frame(width: 40, height: 40)
                    .background(Palette.marginRed.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nächster Schritt")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(step.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Palette.ink)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

/// A learning session in a list.
struct SessionRow: View {
    let session: StudySession
    let topicName: String?
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.status == .done ? "checkmark.circle.fill" : session.kind.symbol)
                .foregroundStyle(session.status == .done ? SubjectColor.green.color : Palette.secondaryInk)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text([topicName, session.kind.title].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(session.status == .skipped ? Palette.faintInk : Palette.ink)
                    .strikethrough(session.status == .skipped, color: Palette.faintInk)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
    }

    private var detail: String {
        var parts: [String] = []
        if showsDate { parts.append(Fmt.shortDay(session.date)) }
        switch session.status {
        case .done: parts.append("\(session.actualMinutes) Min. gelernt")
        case .skipped: parts.append("ausgelassen")
        case .planned: parts.append("\(session.plannedMinutes) Min.")
        }
        return parts.joined(separator: " · ")
    }
}

/// Edits the learning state of one topic.
struct TopicProgressSection: View {
    @Environment(\.modelContext) private var context
    let topicUID: UUID
    @State private var progress: TopicProgress?

    var body: some View {
        Group {
            if let progress {
                Section {
                    UnderstandingPicker(level: Binding(
                        get: { progress.understanding },
                        set: { LearningStore.setUnderstanding($0, topicUID: topicUID, source: "manual", context: context) }
                    ))
                } header: {
                    Text("Wie gut verstehst du das?")
                } footer: {
                    Text("Unabhängig davon, wie viel du schon aufgeschrieben hast.")
                }
                .marginRow()

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Material erledigt", value: "\(Int((progress.completion * 100).rounded())) %")
                        Slider(value: Binding(get: { progress.completion }, set: { progress.completion = $0; save() }), in: 0...1, step: 0.1)
                    }
                    Picker("Wichtigkeit", selection: Binding(get: { progress.importance }, set: { progress.importance = $0; save() })) {
                        Text("Gering").tag(0)
                        Text("Normal").tag(1)
                        Text("Hoch").tag(2)
                    }
                    Picker("Lernaufwand", selection: Binding(get: { progress.estimatedMinutes }, set: { progress.estimatedMinutes = $0; save() })) {
                        ForEach([30, 45, 60, 90, 120, 180, 240, 300], id: \.self) { Text(Fmt.duration(minutes: $0)).tag($0) }
                    }
                    if let last = progress.lastStudied {
                        LabeledContent("Zuletzt gelernt", value: Fmt.relativeDay(last))
                    }
                } header: {
                    Text("Lernstand")
                }
                .marginRow()
            }
        }
        .onAppear {
            progress = LearningStore.progress(for: topicUID, context: context)
        }
    }

    private func save() {
        progress?.updatedAt = .now
        try? context.save()
    }
}
