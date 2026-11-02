import SwiftData
import SwiftUI

struct SubjectEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var subjects: [SchoolSubject]

    private let subject: SchoolSubject?
    @State private var name: String
    @State private var colorKey: String
    @State private var teacher: String
    @State private var room: String
    @State private var notes: String

    init(subject: SchoolSubject?) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _colorKey = State(initialValue: subject?.colorKey ?? SubjectColor.blue.rawValue)
        _teacher = State(initialValue: subject?.teacher ?? "")
        _room = State(initialValue: subject?.room ?? "")
        _notes = State(initialValue: subject?.notes ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Name, z. B. Mathematik", text: $name)
                    .font(.body.weight(.medium))
            }
            .marginRow()

            Section("Farbe") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
                    ForEach(SubjectColor.allCases) { color in
                        Button {
                            colorKey = color.rawValue
                            Haptics.selection()
                        } label: {
                            ZStack {
                                Circle().fill(color.color)
                                if colorKey == color.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.name)
                        .accessibilityAddTraits(colorKey == color.rawValue ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }
            .marginRow()

            Section {
                TextField("Lehrkraft", text: $teacher)
                TextField("Raum", text: $room)
            } footer: {
                Text("Der Raum gilt für alle Stunden, bei denen kein eigener Raum eingetragen ist.")
            }
            .marginRow()

            Section("Notizen") {
                TextField("Bewertung, Materialien, Hinweise …", text: $notes, axis: .vertical)
                    .lineLimit(3...10)
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle(subject == nil ? "Neues Fach" : "Fach bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).disabled(trimmedName.isEmpty)
            }
        }
    }

    private func save() {
        let target: SchoolSubject
        if let subject {
            target = subject
        } else {
            let nextIndex = (subjects.map(\.sortIndex).max() ?? -1) + 1
            target = SchoolSubject(name: trimmedName, colorKey: colorKey, sortIndex: nextIndex)
            context.insert(target)
        }
        target.name = trimmedName
        target.colorKey = colorKey
        target.teacher = teacher.trimmingCharacters(in: .whitespaces)
        target.room = room.trimmingCharacters(in: .whitespaces)
        target.notes = notes
        context.commit()
        Haptics.success()
        dismiss()
    }
}

/// Quick start: pick the usual German school subjects in one go.
struct SubjectTemplatesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var subjects: [SchoolSubject]
    @State private var selected: Set<String> = []

    static let templates: [(name: String, color: SubjectColor)] = [
        ("Deutsch", .red), ("Mathematik", .blue), ("Englisch", .orange), ("Französisch", .pink),
        ("Latein", .brown), ("Spanisch", .mustard), ("Biologie", .green), ("Chemie", .teal),
        ("Physik", .indigo), ("Informatik", .gray), ("Geschichte", .brown), ("Erdkunde", .olive),
        ("Politik", .violet), ("Wirtschaft", .mustard), ("Kunst", .coral), ("Musik", .violet),
        ("Sport", .orange), ("Religion", .olive), ("Ethik", .olive), ("Philosophie", .indigo),
    ]

    private var existingNames: Set<String> {
        Set(subjects.map { $0.name.lowercased() })
    }

    var body: some View {
        List {
            Section {
                ForEach(Self.templates, id: \.name) { template in
                    let exists = existingNames.contains(template.name.lowercased())
                    Button {
                        if selected.contains(template.name) {
                            selected.remove(template.name)
                        } else {
                            selected.insert(template.name)
                        }
                        Haptics.selection()
                    } label: {
                        HStack {
                            SubjectDot(color: template.color.color, size: 12)
                            Text(template.name).foregroundStyle(Palette.ink)
                            Spacer()
                            if exists {
                                Text("vorhanden").font(.caption).foregroundStyle(Palette.secondaryInk)
                            } else {
                                Image(systemName: selected.contains(template.name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(template.name) ? Palette.marginRed : Palette.faintInk)
                            }
                        }
                    }
                    .disabled(exists)
                }
            } footer: {
                Text("Farben, Lehrkraft und Raum kannst du danach bei jedem Fach ändern.")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Fächer auswählen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(selected.isEmpty ? "Hinzufügen" : "Hinzufügen (\(selected.count))", action: add)
                    .disabled(selected.isEmpty)
            }
        }
    }

    private func add() {
        var index = (subjects.map(\.sortIndex).max() ?? -1) + 1
        for template in Self.templates where selected.contains(template.name) {
            context.insert(SchoolSubject(name: template.name, colorKey: template.color.rawValue, sortIndex: index))
            index += 1
        }
        context.commit()
        Haptics.success()
        dismiss()
    }
}
