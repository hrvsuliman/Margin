import SwiftData
import SwiftUI

/// One real lesson from WebUntis or a calendar feed.
struct TimetableEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var subjects: [SchoolSubject]
    let entry: TimetableEntry

    private var subject: SchoolSubject? { entry.subjectUID.flatMap { id in subjects.first { $0.uid == id } } }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    MarginBar(color: subject?.color.color ?? SubjectColor.gray.color, width: 4)
                        .frame(height: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subject?.name ?? entry.subjectName)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .strikethrough(entry.status == .cancelled)
                        Text("\(Fmt.longDay(entry.start)) · \(Fmt.time(entry.start))–\(Fmt.time(entry.end))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            .listRowBackground(Color.clear)

            Section {
                if entry.status != .normal {
                    LabeledContent("Status") {
                        Text(entry.status.title).foregroundStyle(Palette.marginRed)
                    }
                }
                if !entry.room.isEmpty { LabeledContent("Raum", value: entry.room) }
                if !entry.teacher.isEmpty { LabeledContent("Lehrkraft", value: entry.teacher) }
                if !entry.info.isEmpty {
                    Text(entry.info).foregroundStyle(Palette.ink)
                }
                LabeledContent("Quelle", value: entry.source == "untis" ? "WebUntis" : "Kalender")
                LabeledContent("Abgerufen", value: "\(Fmt.shortDay(entry.fetchedAt)), \(Fmt.time(entry.fetchedAt))")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Stunde")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
    }
}

/// Connect WebUntis (or any school calendar) so the timetable, cancellations
/// and substitutions come in automatically.
struct SchoolConnectionView: View {
    @Environment(\.modelContext) private var context
    @State private var sync = SchoolSync.shared
    @State private var password = ""
    @State private var hasPassword = Keychain.read(SchoolSync.passwordAccount) != nil

    var body: some View {
        Form {
            Section {
                Picker("Quelle", selection: $sync.source) {
                    ForEach(SchoolSync.Source.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Margin holt den Stundenplan der nächsten drei Wochen mit Entfall und Vertretungen. Bei Änderungen für heute und morgen bekommst du eine Mitteilung.")
            }
            .marginRow()

            switch sync.source {
            case .untis:
                Section {
                    TextField("Server, z. B. nessa.webuntis.com", text: $sync.server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Schulname (wie beim Untis-Login)", text: $sync.school)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Benutzername", text: $sync.user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if hasPassword {
                        HStack {
                            Text("Passwort gespeichert")
                            Spacer()
                            Button("Ändern") {
                                Keychain.delete(SchoolSync.passwordAccount)
                                hasPassword = false
                            }
                        }
                    } else {
                        SecureField("Passwort", text: $password)
                        Button("Passwort sichern") {
                            hasPassword = Keychain.write(password, account: SchoolSync.passwordAccount)
                            password = ""
                        }
                        .disabled(password.isEmpty)
                    }
                    Toggle("Fehlende Fächer anlegen", isOn: $sync.createMissingSubjects)
                } header: {
                    Text("WebUntis")
                } footer: {
                    Text("Server und Schulname findest du in der Adresse, wenn du dich im Browser bei WebUntis anmeldest (…webuntis.com/WebUntis/?school=…). Das Passwort bleibt im Schlüsselbund dieses iPhones. Ob Schüler-Zugänge den Stundenplan abrufen dürfen, entscheidet deine Schule – sonst nimm den Kalender-Link.")
                }
                .marginRow()
            case .ical:
                Section {
                    TextField("https://… oder webcal://…", text: $sync.icalURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Kalender-Link")
                } footer: {
                    Text("In WebUntis: Profil › Freigaben › iCal-Link erstellen. Funktioniert auch mit anderen Schulkalendern.")
                }
                .marginRow()
            case .off:
                EmptyView()
            }

            if sync.source != .off {
                Section {
                    Button {
                        Task { await sync.refresh(context: context) }
                    } label: {
                        HStack {
                            Label("Jetzt abrufen", systemImage: "arrow.down.circle")
                            Spacer()
                            if sync.syncing { ProgressView() }
                        }
                    }
                    .disabled(!sync.isConfigured || sync.syncing)
                    if let last = sync.lastSync {
                        LabeledContent("Zuletzt", value: "\(Fmt.shortDay(last)), \(Fmt.time(last))")
                    }
                    if let error = sync.lastError {
                        Text(error).font(.footnote).foregroundStyle(Palette.marginRed)
                    }
                } footer: {
                    Text("Wird beim Öffnen der App und – wenn iOS es erlaubt – im Hintergrund aktualisiert.")
                }
                .marginRow()
            }
        }
        .marginList()
        .navigationTitle("Stundenplan verbinden")
        .navigationBarTitleDisplayMode(.inline)
    }
}
