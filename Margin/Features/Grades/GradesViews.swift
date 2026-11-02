import SwiftData
import SwiftUI

/// All subjects with their averages, plus the overall average.
struct GradesView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    @Query(sort: \Grade.date) private var grades: [Grade]
    @Query private var setups: [GradeSetup]

    private var scale: GradeScale { settings.gradeScale }

    private func average(for subject: SchoolSubject) -> Double? {
        let share = setups.first { $0.subjectUID == subject.uid }?.writtenShare ?? 0.5
        return GradeMath.average(entries(for: subject), writtenShare: share)
    }

    private func entries(for subject: SchoolSubject) -> [GradeEntry] {
        grades.filter { $0.subjectUID == subject.uid }
            .map { GradeEntry(value: $0.value, weight: $0.weight, isWritten: $0.kind.isWritten) }
    }

    private var overall: Double? {
        let averages = subjects.compactMap(average(for:))
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gesamtschnitt")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(overall.map(scale.average) ?? "–")
                        .font(.system(size: 44, weight: .semibold, design: .serif).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                    Text("Mittelwert der Fächer mit Noten")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                ForEach(subjects) { subject in
                    NavigationLink {
                        SubjectGradesView(subject: subject)
                    } label: {
                        HStack {
                            SubjectDot(color: subject.color.color, size: 10)
                            Text(subject.name).foregroundStyle(Palette.ink)
                            Spacer()
                            let count = grades.filter { $0.subjectUID == subject.uid }.count
                            if let value = average(for: subject) {
                                Text(scale.average(value))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(Palette.ink)
                                Text("(\(count))")
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            } else {
                                Text("keine Noten").font(.caption).foregroundStyle(Palette.faintInk)
                            }
                        }
                    }
                }
            } header: {
                SectionTitle("Fächer")
            } footer: {
                Text("Nur auf diesem iPhone. Margin rechnet mit deiner Gewichtung – deine Schule kann anders runden oder gewichten.")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Noten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Skala", selection: Binding(get: { settings.gradeScale }, set: { settings.gradeScale = $0 })) {
                        ForEach(GradeScale.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Notenskala")
            }
        }
    }
}

/// One subject: its grades, the weighting, a goal and what the next test needs.
struct SubjectGradesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    let subject: SchoolSubject
    @Query(sort: \Grade.date, order: .reverse) private var allGrades: [Grade]
    @Query private var setups: [GradeSetup]
    @State private var editing: Grade?
    @State private var adding = false

    private var scale: GradeScale { settings.gradeScale }
    private var grades: [Grade] { allGrades.filter { $0.subjectUID == subject.uid } }
    private var setup: GradeSetup? { setups.first { $0.subjectUID == subject.uid } }
    private var entries: [GradeEntry] {
        grades.map { GradeEntry(value: $0.value, weight: $0.weight, isWritten: $0.kind.isWritten) }
    }
    private var share: Double { setup?.writtenShare ?? 0.5 }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Schnitt").font(.caption).foregroundStyle(Palette.secondaryInk)
                        Text(GradeMath.average(entries, writtenShare: share).map(scale.average) ?? "–")
                            .font(.system(size: 40, weight: .semibold, design: .serif).monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        part("Schriftlich", entries.filter(\.isWritten))
                        part("Mündlich/Sonstige", entries.filter { !$0.isWritten })
                    }
                }
            }
            .listRowBackground(Color.clear)

            Section {
                VStack(alignment: .leading) {
                    LabeledContent("Schriftlich zählt", value: "\(Int((share * 100).rounded())) %")
                    Slider(value: Binding(get: { share }, set: { ensureSetup().writtenShare = $0; try? context.save() }),
                           in: 0...1, step: 0.05)
                }
                Picker("Ziel", selection: Binding(get: { setup?.goal }, set: { ensureSetup().goal = $0; try? context.save() })) {
                    Text("Kein Ziel").tag(nil as Double?)
                    ForEach(goalOptions, id: \.self) { Text(scale.label($0)).tag($0 as Double?) }
                }
                if let goal = setup?.goal {
                    if let needed = GradeMath.neededNext(entries, writtenShare: share, target: goal, scale: scale) {
                        Label("Für \(scale.label(goal)) brauchst du in der nächsten Arbeit mindestens \(scale.label(needed)).",
                              systemImage: "target")
                            .foregroundStyle(Palette.ink)
                    } else {
                        Label("\(scale.label(goal)) ist mit einer weiteren Arbeit nicht mehr erreichbar – aber mündlich geht noch was.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.marginRed)
                    }
                }
            } header: {
                SectionTitle("Gewichtung und Ziel")
            }
            .marginRow()

            Section {
                if grades.isEmpty {
                    Text("Noch keine Noten.").foregroundStyle(Palette.secondaryInk)
                }
                ForEach(grades) { grade in
                    Button {
                        editing = grade
                    } label: {
                        HStack {
                            Text(scale.label(grade.value))
                                .font(.system(.title3, design: .serif, weight: .semibold).monospacedDigit())
                                .frame(width: 52, alignment: .leading)
                                .foregroundStyle(Palette.ink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(grade.title.isEmpty ? grade.kind.title : grade.title).foregroundStyle(Palette.ink)
                                Text("\(grade.kind.title) · \(Fmt.date(grade.date))\(grade.weight != 1 ? " · ×\(String(format: "%g", grade.weight))" : "")")
                                    .font(.caption)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(grades[index]) }
                    try? context.save()
                }
            } header: {
                SectionTitle("Noten", trailing: "\(grades.count)")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Note eintragen")
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { GradeEditor(grade: nil, subjectUID: subject.uid, examUID: nil) }
                .tint(Palette.marginRed)
        }
        .sheet(item: $editing) { grade in
            NavigationStack { GradeEditor(grade: grade, subjectUID: subject.uid, examUID: grade.examUID) }
                .tint(Palette.marginRed)
        }
    }

    private var goalOptions: [Double] {
        scale == .grades ? [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0] : [15, 13, 11, 10, 9, 7, 5]
    }

    private func part(_ title: String, _ list: [GradeEntry]) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Palette.secondaryInk)
            Text(GradeMath.weightedAverage(list).map(scale.average) ?? "–")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
    }

    private func ensureSetup() -> GradeSetup {
        if let setup { return setup }
        let created = GradeSetup(subjectUID: subject.uid)
        context.insert(created)
        return created
    }
}

struct GradeEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \SchoolSubject.sortIndex) private var subjects: [SchoolSubject]
    let grade: Grade?

    @State private var subjectUID: UUID?
    @State private var examUID: UUID?
    @State private var value: Double
    @State private var kind: GradeKind
    @State private var weight: Double
    @State private var title: String
    @State private var date: Date

    init(grade: Grade?, subjectUID: UUID?, examUID: UUID?, kind: GradeKind = .written, title: String = "") {
        self.grade = grade
        _subjectUID = State(initialValue: grade?.subjectUID ?? subjectUID)
        _examUID = State(initialValue: grade?.examUID ?? examUID)
        _value = State(initialValue: grade?.value ?? (AppSettings.shared.gradeScale == .grades ? 2 : 10))
        _kind = State(initialValue: grade?.kind ?? kind)
        _weight = State(initialValue: grade?.weight ?? 1)
        _title = State(initialValue: grade?.title ?? title)
        _date = State(initialValue: grade?.date ?? .now)
    }

    private var scale: GradeScale { settings.gradeScale }

    var body: some View {
        Form {
            Section {
                Picker("Note", selection: $value) {
                    ForEach(scale.options, id: \.self) { Text(scale.label($0)).tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 140)
            }
            .marginRow()
            Section {
                Picker("Fach", selection: $subjectUID) {
                    Text("Bitte wählen").tag(nil as UUID?)
                    ForEach(subjects) { Text($0.name).tag($0.uid as UUID?) }
                }
                Picker("Art", selection: $kind) {
                    ForEach(GradeKind.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: $weight, in: 0.5...4, step: 0.5) {
                    LabeledContent("Gewicht", value: "×\(String(format: "%g", weight))")
                }
                TextField("Titel (optional), z. B. 2. Klassenarbeit", text: $title)
                DatePicker("Datum", selection: $date, displayedComponents: .date)
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(grade == nil ? "Note eintragen" : "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).disabled(subjectUID == nil)
            }
        }
    }

    private func save() {
        let target = grade ?? Grade(subjectUID: subjectUID, value: value, kind: kind)
        if grade == nil { context.insert(target) }
        target.subjectUID = subjectUID
        target.examUID = examUID
        target.value = value
        target.kind = kind
        target.weight = weight
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.date = date
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
