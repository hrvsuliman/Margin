import SwiftData
import SwiftUI

/// What to write next in a capture session.
enum CaptureItem: Hashable, Identifiable {
    case character(String)
    case sampleWord(String)

    var id: String {
        switch self {
        case .character(let c): "c-\(c)"
        case .sampleWord(let w): "w-\(w)"
        }
    }

    var text: String {
        switch self {
        case .character(let c): c
        case .sampleWord(let w): w
        }
    }
}

/// Guided writing: one character (or the sample word) at a time, on guide lines.
struct CaptureFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let profile: HandwritingProfile
    let items: [CaptureItem]
    var title = "Handschrift"

    @StateObject private var canvas = CaptureController()
    @State private var index = 0
    @State private var saved = 0
    @State private var spacingResult: Double?

    private var item: CaptureItem? { items.indices.contains(index) ? items[index] : nil }
    private var isWord: Bool {
        if case .sampleWord = item { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    writing(item)
                } else {
                    finished
                }
            }
            .background(Palette.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .tint(Palette.marginRed)
        .interactiveDismissDisabled()
    }

    private func writing(_ item: CaptureItem) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                ProgressView(value: Double(index), total: Double(max(items.count, 1)))
                    .tint(Palette.marginRed)
                Text("\(index + 1) von \(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.secondaryInk)
            }
            .padding(.horizontal)

            VStack(spacing: 4) {
                Text(isWord ? "Schreib dieses Wort in einem Zug:" : "Schreib groß und langsam:")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                Text(item.text)
                    .font(.system(size: isWord ? 34 : 56, weight: .regular, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                    .id(item.id)
                Text(isWord ? "So weit auseinander, wie du normal schreibst. Daraus wird der Buchstabenabstand gemessen."
                     : HandwritingCharset.hint(for: item.text))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            StrokeCanvas(controller: canvas)
                .background(PaperInk.paper)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.ruling, lineWidth: 1))
                .aspectRatio(isWord ? 2.4 : 0.92, contentMode: .fit)
                .padding(.horizontal, isWord ? 6 : 14)
                .id("canvas-\(item.id)")

            HStack(spacing: 12) {
                Button {
                    canvas.undo()
                } label: {
                    Label("Rückgängig", systemImage: "arrow.uturn.backward")
                }
                .disabled(canvas.isEmpty)
                Button {
                    canvas.clear()
                } label: {
                    Label("Löschen", systemImage: "eraser")
                }
                .disabled(canvas.isEmpty)
                Spacer()
                Button("Überspringen") { advance() }
                    .foregroundStyle(Palette.secondaryInk)
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .padding(.horizontal, 28)

            Button {
                save(item)
            } label: {
                Text(index == items.count - 1 ? "Sichern" : "Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.ink)
            .foregroundStyle(Palette.paper)
            .disabled(canvas.isEmpty)
            .padding(.horizontal, 28)

            if !isWord {
                upcoming
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private var upcoming: some View {
        HStack(spacing: 10) {
            ForEach(items.dropFirst(index + 1).prefix(10)) { next in
                Text(next.text)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Palette.faintInk)
            }
        }
        .accessibilityHidden(true)
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.marginRed)
            Text("Geschafft")
                .font(.system(.title, design: .serif, weight: .semibold))
            Text("\(saved) Zeichen gespeichert.")
                .foregroundStyle(Palette.secondaryInk)
            if let spacingResult {
                Text("Gemessener Buchstabenabstand: \(String(format: "%.2f", spacingResult)) × x-Höhe")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Button("Zur Vorschau") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ink)
                .foregroundStyle(Palette.paper)
                .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func save(_ item: CaptureItem) {
        guard let strokes = GlyphProcessing.normalize(canvas.strokes, guide: canvas.guide) else { return }
        switch item {
        case .character(let character):
            let sample = GlyphSample(character: character, strokeData: GlyphStrokes.encode(strokes))
            context.insert(sample)
            sample.profile = profile
            saved += 1
        case .sampleWord(let word):
            let source = FontSource(profile: profile)
            if let gap = HandwritingAnalysis.letterSpacing(word: word, written: strokes, glyphs: source.glyphs) {
                profile.letterSpacing = gap
                profile.spacingMeasured = true
                spacingResult = gap
            }
        }
        profile.touch()
        try? context.save()
        Haptics.success()
        advance()
    }

    private func advance() {
        canvas.clear()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            index += 1
        }
    }
}
