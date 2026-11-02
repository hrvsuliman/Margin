import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// What a focus session is about.
struct FocusRequest: Identifiable {
    let id = UUID()
    var topicUID: UUID?
    var subjectUID: UUID?
    var examUID: UUID?
    var minutes: Int
    /// The planned session this fulfils, if any.
    var session: StudySession?
}

/// A calm full-screen timer. Time is measured with dates, so it stays correct
/// when the phone is locked; a notification announces the end.
struct FocusView: View {
    enum Phase { case setup, running, finished }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query private var topics: [Topic]

    let request: FocusRequest
    @State private var minutes: Int
    @State private var topicUID: UUID?
    @State private var subjectUID: UUID?
    @State private var phase: Phase = .setup
    @State private var endDate = Date.now
    @State private var pausedRemaining: TimeInterval?
    @State private var startedAt = Date.now
    @State private var studiedSeconds: TimeInterval = 0
    @State private var level: Understanding = .notYet

    private static let notificationID = "focus-end"

    init(request: FocusRequest) {
        self.request = request
        _minutes = State(initialValue: request.minutes)
        _topicUID = State(initialValue: request.topicUID)
        _subjectUID = State(initialValue: request.subjectUID)
    }

    private var topicName: String? {
        topicUID.flatMap { id in topics.first { $0.uid == id }?.title }
    }
    private var subject: SchoolSubject? {
        subjectUID.flatMap { id in subjects.first { $0.uid == id } }
    }

    var body: some View {
        ZStack {
            RuledPaper(lineSpacing: 38, marginX: 32)
            switch phase {
            case .setup: setup
            case .running: running
            case .finished: finished
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: phase)
        .onDisappear { cancelNotification() }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 24) {
            HStack {
                Button("Abbrechen") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 24)
            Spacer()
            Text("Fokuszeit")
                .font(.system(size: 40, weight: .semibold, design: .serif))
            Text(topicName ?? subject?.name ?? "Freies Lernen")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Palette.secondaryInk)

            HStack(spacing: 10) {
                ForEach([15, 25, 45, 60], id: \.self) { option in
                    Button {
                        minutes = option
                        Haptics.selection()
                    } label: {
                        Text("\(option)")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .frame(width: 62, height: 62)
                            .foregroundStyle(minutes == option ? Palette.paper : Palette.ink)
                            .background(minutes == option ? Palette.ink : Palette.sheet, in: Circle())
                            .overlay(Circle().stroke(Palette.ruling))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option) Minuten")
                }
            }

            if request.topicUID == nil {
                Menu {
                    Picker("Fach", selection: $subjectUID) {
                        Text("Kein Fach").tag(nil as UUID?)
                        ForEach(subjects) { Text($0.name).tag($0.uid as UUID?) }
                    }
                } label: {
                    Label(subject?.name ?? "Fach wählen", systemImage: "books.vertical")
                        .font(.subheadline)
                }
            }
            Spacer()
            Button(action: start) {
                Text("Los geht's")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.ink)
            .foregroundStyle(Palette.paper)
            .padding(.horizontal, 32)
            Text("Handy weglegen. Die Zeit läuft auch weiter, wenn du es sperrst.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.bottom, 24)
        }
        .padding(.top, 12)
    }

    // MARK: Running

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = pausedRemaining ?? max(0, endDate.timeIntervalSince(timeline.date))
            let total = Double(minutes * 60)
            VStack(spacing: 28) {
                Spacer()
                Text(topicName ?? subject?.name ?? "Fokus")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.secondaryInk)
                ZStack {
                    Circle().stroke(Palette.ruling, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - remaining / total))
                        .stroke(Palette.marginRed, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                    Text(clock(remaining))
                        .font(.system(size: 64, weight: .light, design: .serif).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 260, height: 260)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Noch \(Int(remaining / 60)) Minuten")
                Spacer()
                HStack(spacing: 20) {
                    Button {
                        togglePause(remaining: remaining)
                    } label: {
                        Label(pausedRemaining == nil ? "Pause" : "Weiter",
                              systemImage: pausedRemaining == nil ? "pause.fill" : "play.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.ink)
                    Button {
                        finish(remaining: remaining)
                    } label: {
                        Label("Fertig", systemImage: "checkmark")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .foregroundStyle(Palette.paper)
                }
                .padding(.bottom, 40)
            }
            .onChange(of: remaining <= 0) {
                if remaining <= 0 && phase == .running {
                    Haptics.success()
                    finish(remaining: 0)
                }
            }
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Finished

    private var finished: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Palette.marginRed)
            Text("\(max(1, Int((studiedSeconds / 60).rounded()))) Minuten gelernt")
                .font(.system(.title, design: .serif, weight: .semibold))
            if let topicName {
                Text("Wie gut sitzt „\(topicName)“ jetzt?")
                    .font(.headline)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    UnderstandingPicker(level: $level)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                }
                .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
            }
            Spacer()
            Button {
                save()
                dismiss()
            } label: {
                Text("Sichern")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.ink)
            .foregroundStyle(Palette.paper)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .onAppear {
            if let topicUID {
                level = LearningStore.progress(for: topicUID, context: context).understanding
            }
        }
    }

    // MARK: Actions

    private func start() {
        startedAt = .now
        endDate = Date.now.addingTimeInterval(Double(minutes * 60))
        pausedRemaining = nil
        phase = .running
        scheduleNotification(at: endDate)
        UIApplication.shared.isIdleTimerDisabled = true
        Haptics.tap()
    }

    private func togglePause(remaining: TimeInterval) {
        if let paused = pausedRemaining {
            endDate = Date.now.addingTimeInterval(paused)
            pausedRemaining = nil
            scheduleNotification(at: endDate)
        } else {
            pausedRemaining = remaining
            cancelNotification()
        }
        Haptics.selection()
    }

    private func finish(remaining: TimeInterval) {
        studiedSeconds = max(60, Double(minutes * 60) - remaining)
        cancelNotification()
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .finished
    }

    private func save() {
        let studied = max(1, Int((studiedSeconds / 60).rounded()))
        if let session = request.session {
            LearningStore.complete(session, minutes: studied, context: context)
        } else {
            LearningStore.logFreeSession(topicUID: topicUID, subjectUID: subjectUID, minutes: studied, context: context)
        }
        if let topicUID {
            LearningStore.setUnderstanding(level, topicUID: topicUID, source: "session", context: context)
        }
        Haptics.success()
    }

    private func scheduleNotification(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Fokuszeit vorbei"
        content.body = "Gut gemacht. Kurz durchatmen, dann eintragen, wie gut es jetzt sitzt."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }
}
