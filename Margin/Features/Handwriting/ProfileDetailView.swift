import SwiftData
import SwiftUI

/// A handwriting profile: preview, analysis, fine-tuning and all characters.
struct ProfileDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [HandwritingProfile]
    @Bindable var profile: HandwritingProfile

    @State private var font: HandwritingFont?
    @State private var capture: CaptureSession?
    @State private var confirmDelete = false
    @State private var showPenScan = false

    private var analysis: HandwritingAnalysis? { font?.analysis }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $profile.name)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                HandwritingSampleView(text: HandwritingCharset.pangram, font: font, lines: 3)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                Toggle("Standard für neue Notizen", isOn: defaultBinding)
            }
            .marginRow()

            Section {
                Button {
                    showPenScan = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mit Stift auf Papier").font(.body.weight(.semibold))
                            Text("Vorlage drucken, ausfüllen, scannen – empfohlen")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    } icon: {
                        Image(systemName: "doc.viewfinder")
                    }
                }
            } header: {
                Text("Schriftproben")
            } footer: {
                Text("Mit deinem echten Stift sieht das Ergebnis am natürlichsten aus. Einzelne Zeichen kannst du jederzeit auch mit dem Finger ergänzen.")
            }
            .marginRow()

            Section {
                if let missing = analysis?.missing, !missing.isEmpty {
                    Button {
                        capture = CaptureSession.missing(for: profile)
                    } label: {
                        Label("Fehlende Zeichen mit dem Finger (\(missing.count))", systemImage: "hand.draw")
                    }
                } else if !profile.spacingMeasured {
                    Button {
                        capture = CaptureSession(profile: profile, items: [.sampleWord(HandwritingCharset.sampleWord)],
                                                 title: "Probewort")
                    } label: {
                        Label("Probewort schreiben (Abstand messen)", systemImage: "textformat.abc")
                    }
                }
                Button {
                    capture = CaptureSession.variants(for: profile)
                } label: {
                    Label("Varianten mit dem Finger", systemImage: "square.stack.3d.up")
                }
            } header: {
                Text("Mit dem Finger")
            } footer: {
                Text("Mehrere Versionen eines Buchstabens sorgen dafür, dass Wiederholungen nicht wie kopiert aussehen.")
            }
            .marginRow()

            if let analysis {
                analysisSection(analysis)
            }

            tuningSection

            ForEach(HandwritingCharset.groups, id: \.title) { group in
                Section(group.title) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(group.characters, id: \.self) { character in
                            NavigationLink {
                                GlyphDetailView(profile: profile, character: character)
                            } label: {
                                GlyphTile(variant: font?.variants(for: Character(character))?.first, character: character)
                                    .aspectRatio(0.9, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(alignment: .topTrailing) {
                                        let count = profile.samples(for: character).count
                                        if count > 1 {
                                            Text("\(count)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Palette.secondaryInk)
                                                .padding(3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .marginRow()
            }

            Section {
                Button("Handschrift löschen", role: .destructive) { confirmDelete = true }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(profile.name.isEmpty ? "Handschrift" : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .loadsFont(of: profile, into: $font)
        .fullScreenCover(item: $capture) { session in
            CaptureFlowView(profile: session.profile, items: session.items, title: session.title)
        }
        .sheet(isPresented: $showPenScan) {
            NavigationStack { PenScanView(profile: profile) }
                .tint(Palette.marginRed)
        }
        .onChange(of: profile.name) { profile.touch() }
        .onDisappear { try? context.save() }
        .confirmationDialog("Handschrift löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                let profile = profile
                let context = context
                dismiss()
                Deferred.afterDismiss {
                    context.delete(profile)
                    context.commit()
                }
            }
        } message: {
            Text("Alle Schriftproben dieses Profils werden gelöscht.")
        }
    }

    private func analysisSection(_ analysis: HandwritingAnalysis) -> some View {
        Section {
            LabeledContent("Zeichen", value: "\(analysis.captured) von \(analysis.total)")
            LabeledContent("Schriftproben", value: "\(analysis.variantCount)")
            LabeledContent("Größe", value: sizeText(analysis.scaleCorrection))
            LabeledContent("Neigung", value: slantText(analysis.slantDegrees))
            LabeledContent("Gleichmäßigkeit", value: "\(Int((analysis.consistency * 100).rounded())) %")
            LabeledContent("Buchstabenabstand", value: profile.spacingMeasured ? "gemessen" : "Standardwert")
            if !analysis.outliers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auffällig groß oder klein: \(Set(analysis.outliers.map(\.character)).sorted().joined(separator: " "))")
                        .font(.subheadline)
                    Button("Größe automatisch angleichen") { fixOutliers(analysis.outliers) }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Analyse")
        } footer: {
            Text("Größe und Grundlinie werden automatisch ausgeglichen, damit alle Zeichen gleich hoch auf der Linie stehen.")
        }
        .marginRow()
    }

    private var tuningSection: some View {
        Section {
            slider("Buchstabenabstand", value: $profile.letterSpacing, range: 0...0.8)
            slider("Wortabstand", value: $profile.wordSpacing, range: 0.3...1.8)
            slider("Neigung", value: $profile.slantAdjust, range: -15...15, unit: "°")
            slider("Natürliche Variation", value: $profile.variation, range: 0...2)
            Button("Zurücksetzen") {
                profile.letterSpacing = 0.14
                profile.wordSpacing = 0.75
                profile.slantAdjust = 0
                profile.variation = 1
                profile.spacingMeasured = false
                profile.touch()
            }
        } header: {
            Text("Feinabstimmung")
        } footer: {
            Text("Variation verändert Grundlinie, Größe, Drehung und Abstände leicht – wie beim echten Schreiben.")
        }
        .marginRow()
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue) + unit)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.secondaryInk)
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0; profile.touch() }
            ), in: range)
        }
    }

    private var defaultBinding: Binding<Bool> {
        Binding(
            get: { profile.isDefault },
            set: { isOn in
                for other in profiles { other.isDefault = false }
                profile.isDefault = isOn || profiles.count == 1
                try? context.save()
            }
        )
    }

    private func sizeText(_ correction: Double) -> String {
        if abs(correction - 1) < 0.05 { return "passt zu den Linien" }
        return correction > 1 ? "kleiner geschrieben, ×\(String(format: "%.2f", correction)) vergrößert"
            : "größer geschrieben, ×\(String(format: "%.2f", correction)) verkleinert"
    }

    private func slantText(_ degrees: Double) -> String {
        if abs(degrees) < 2 { return "aufrecht" }
        return "\(Int(abs(degrees).rounded()))° nach \(degrees > 0 ? "rechts" : "links")"
    }

    private func fixOutliers(_ outliers: [HandwritingAnalysis.Outlier]) {
        let samples = profile.glyphs ?? []
        for outlier in outliers {
            samples.first { $0.uid == outlier.glyphUID }?.scale = min(max(outlier.suggestedScale, 0.5), 1.8)
        }
        profile.touch()
        try? context.save()
        Haptics.success()
    }
}

/// All versions of one character, with size and baseline correction.
struct GlyphDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: HandwritingProfile
    let character: String

    @State private var font: HandwritingFont?
    @State private var capture: CaptureSession?

    private var samples: [GlyphSample] { profile.samples(for: character) }

    var body: some View {
        List {
            Section {
                HandwritingSampleView(text: "\(character)\(character)\(character) \(contextWord)", font: font, lines: 1, lineSpacingMM: 12)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } footer: {
                Text(HandwritingCharset.hint(for: character))
            }
            .marginRow()

            if samples.isEmpty {
                Section {
                    Text("Dieses Zeichen hast du noch nicht geschrieben. Bis dahin erscheint es in einer Ersatzschrift.")
                        .foregroundStyle(Palette.secondaryInk)
                }
                .marginRow()
            }

            ForEach(Array(samples.enumerated()), id: \.element.uid) { index, sample in
                Section("Version \(index + 1)") {
                    GlyphTile(variant: variant(for: sample), character: character)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    correctionSlider("Größe", value: sampleBinding(sample, \.scale), range: 0.5...1.8)
                    correctionSlider("Höhe auf der Linie", value: sampleBinding(sample, \.baselineOffset), range: -0.5...0.5)
                    Button("Version löschen", role: .destructive) {
                        context.delete(sample)
                        profile.touch()
                        try? context.save()
                    }
                }
                .marginRow()
            }

            Section {
                Button {
                    capture = CaptureSession(profile: profile, items: [.character(character)], title: "„\(character)“")
                } label: {
                    Label(samples.isEmpty ? "Jetzt schreiben" : "Weitere Version schreiben", systemImage: "pencil.and.outline")
                }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("„\(character)“")
        .navigationBarTitleDisplayMode(.inline)
        .loadsFont(of: profile, into: $font)
        .fullScreenCover(item: $capture) { session in
            CaptureFlowView(profile: session.profile, items: session.items, title: session.title)
        }
    }

    private var contextWord: String {
        let words = ["Handschrift", "Mathematik", "Physik", "Grundlagen", "Übung", "Zwölf", "Jahr", "Quiz", "Vokabel"]
        return words.first { $0.contains(character) } ?? "Schule"
    }

    private func variant(for sample: GlyphSample) -> HandwritingFont.Variant? {
        guard let font else { return nil }
        let geometry = GlyphStrokes.decodeGlyph(sample.strokeData)
        let input = GlyphInput(uid: sample.uid, strokes: geometry.strokes,
                               scale: sample.scale, baselineOffset: sample.baselineOffset, outlines: geometry.outlines)
        return HandwritingFont.makeVariant(input, analysis: font.analysis, penRatio: font.penRatio)
    }

    private func sampleBinding(_ sample: GlyphSample, _ keyPath: ReferenceWritableKeyPath<GlyphSample, Double>) -> Binding<Double> {
        Binding(
            get: { sample[keyPath: keyPath] },
            set: {
                sample[keyPath: keyPath] = $0
                profile.touch()
            }
        )
    }

    private func correctionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.secondaryInk)
            }
            Slider(value: value, in: range)
        }
    }
}
