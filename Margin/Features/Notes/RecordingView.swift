import AVFoundation
import Speech
import SwiftData
import SwiftUI

/// Records a lesson, turns it into text on the iPhone (German speech
/// recognition) and saves it as a note – ready to be summarised by the tutor
/// and shown in your handwriting.
struct RecordingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    var onCreated: (NoteDocument) -> Void

    enum Phase { case ready, recording, transcribing, failed(String) }

    @State private var phase: Phase = .ready
    @State private var subjectUID: UUID?
    @State private var recorder: AVAudioRecorder?
    @State private var fileURL: URL?
    @State private var startedAt = Date.now
    @State private var level: Float = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                switch phase {
                case .ready:
                    Image(systemName: "waveform")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(Palette.marginRed)
                    Text("Stunde aufnehmen")
                        .font(.system(.title, design: .serif, weight: .semibold))
                    Text("Bitte nur mit Erlaubnis der Lehrkraft aufnehmen. Die Aufnahme wird auf dem iPhone in Text umgewandelt – nichts wird gesendet.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Picker("Fach", selection: $subjectUID) {
                        Text("Kein Fach").tag(nil as UUID?)
                        ForEach(subjects) { Text($0.name).tag($0.uid as UUID?) }
                    }
                    Button(action: start) {
                        Label("Aufnahme starten", systemImage: "record.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.marginRed)
                    .padding(.horizontal, 32)
                case .recording:
                    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                        VStack(spacing: 16) {
                            Circle()
                                .fill(Palette.marginRed)
                                .frame(width: 18 + CGFloat(level) * 40, height: 18 + CGFloat(level) * 40)
                                .animation(.easeOut(duration: 0.4), value: level)
                                .frame(height: 60)
                            Text(Self.clock(timeline.date.timeIntervalSince(startedAt)))
                                .font(.system(size: 48, weight: .light, design: .serif).monospacedDigit())
                        }
                        .onChange(of: timeline.date) {
                            recorder?.updateMeters()
                            let power = recorder?.averagePower(forChannel: 0) ?? -60
                            level = max(0, min(1, (power + 50) / 50))
                        }
                    }
                    Text("Läuft weiter, wenn du das iPhone sperrst.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                    Button(action: stop) {
                        Label("Stoppen und umwandeln", systemImage: "stop.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, 32)
                case .transcribing:
                    ProgressView()
                    Text("Wird in Text umgewandelt …")
                        .font(.headline)
                    Text("Bei langen Aufnahmen dauert das einige Minuten. Lass Margin geöffnet.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(Palette.marginRed)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Palette.paper)
            .navigationTitle("Aufnahme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        recorder?.stop()
                        dismiss()
                    }
                }
            }
        }
        .tint(Palette.marginRed)
        .interactiveDismissDisabled()
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Recording

    private func start() {
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                phase = .failed("Margin darf das Mikrofon nicht benutzen. Erlaube es in den iOS-Einstellungen › Margin.")
                return
            }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .spokenAudio)
                try session.setActive(true)
                let name = "Aufnahme-\(UUID().uuidString).m4a"
                let url = AttachmentStore.directory.appendingPathComponent(name)
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ])
                recorder.isMeteringEnabled = true
                recorder.record()
                self.recorder = recorder
                fileURL = url
                startedAt = .now
                phase = .recording
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                phase = .failed("Aufnahme nicht möglich: \(error.localizedDescription)")
            }
        }
    }

    private func stop() {
        let duration = recorder?.currentTime ?? Date.now.timeIntervalSince(startedAt)
        recorder?.stop()
        recorder = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let url = fileURL else { return }
        phase = .transcribing
        Task {
            let transcript = await Transcriber.transcribe(url)
            let subject = subjects.first { $0.uid == subjectUID }
            let note = NoteDocument(title: "Mitschrift\(subject.map { " \($0.name)" } ?? "") \(Fmt.date(.now))")
            note.subjectUID = subjectUID
            note.folder = "Mitschriften"
            switch transcript {
            case .success(let text):
                note.body = Transcriber.paragraphs(text)
            case .failure(let error):
                note.body = "(Die Aufnahme konnte nicht in Text umgewandelt werden: \(error.localizedDescription). Die Audiodatei ist gespeichert.)"
            }
            context.insert(note)
            context.insert(NoteAudio(noteUID: note.uid, storedName: url.lastPathComponent, duration: duration))
            try? context.save()
            Haptics.success()
            dismiss()
            onCreated(note)
        }
    }
}

/// On-device German speech recognition for recorded audio files.
enum Transcriber {
    static func transcribe(_ url: URL) async -> Result<String, Error> {
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard authorized else {
            return .failure(TranscriberError("Spracherkennung ist nicht erlaubt (iOS-Einstellungen › Margin)."))
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE")), recognizer.isAvailable else {
            return .failure(TranscriberError("Deutsche Spracherkennung ist auf diesem iPhone gerade nicht verfügbar."))
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        return await withCheckedContinuation { continuation in
            var finished = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                // Keep the recognizer and the task alive until the result arrives.
                _ = recognizer
                _ = task
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: .success(result.bestTranscription.formattedString))
                } else if let error {
                    finished = true
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }

    /// Breaks a long transcript into readable paragraphs of a few sentences.
    static func paragraphs(_ text: String) -> String {
        var paragraphs: [String] = []
        var current: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            current.append(sentence)
            if current.count == 4 {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs.joined(separator: "\n\n")
    }
}

struct TranscriberError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
