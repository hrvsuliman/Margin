import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingBackup: BackupFile?
    @State private var confirmWipe = false
    @State private var message: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Schulform", selection: $settings.schoolType) {
                    ForEach(SchoolType.allCases) { Text($0.title).tag($0) }
                }
                NavigationLink("Unterrichtstage") { SchoolDaysView() }
                NavigationLink {
                    PeriodScheduleView()
                } label: {
                    LabeledContent("Stundenraster", value: "\(settings.periods.count) Stunden")
                }
                NavigationLink("Ferien und freie Tage") { HolidaysView() }
                Picker("Notenskala", selection: $settings.gradeScale) {
                    ForEach(GradeScale.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Schule")
            } footer: {
                Text("Die Schulform bestimmt z. B., ob neue Prüfungen als Klassenarbeit oder Klausur angelegt werden.")
            }
            .marginRow()

            Section {
                LabeledContent("Mitteilungen", value: statusText)
                if notificationStatus == .notDetermined {
                    Button("Mitteilungen erlauben") {
                        Task {
                            await ReminderService.requestPermission()
                            await refreshStatus()
                            await ReminderService.refresh(context: context)
                        }
                    }
                } else if notificationStatus == .denied {
                    Button("In den iOS-Einstellungen erlauben") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Picker("Für Aufgaben", selection: $settings.defaultTaskReminder) {
                    ForEach(DefaultTaskReminder.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Erinnerungen")
            } footer: {
                Text("Gilt für offene Aufgaben mit Fälligkeitsdatum, die keine eigene Erinnerung haben.")
            }
            .marginRow()

            Section {
                NavigationLink {
                    ProfilesView()
                } label: {
                    Label("Handschrift", systemImage: "signature")
                }
            } footer: {
                Text("Deine Schriftproben bleiben auf diesem iPhone.")
            }
            .marginRow()

            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
            }
            .marginRow()

            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("Backup sichern", systemImage: "square.and.arrow.up")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Backup wiederherstellen", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    confirmWipe = true
                } label: {
                    Label("Alle Daten löschen", systemImage: "trash")
                }
            } header: {
                Text("Daten")
            } footer: {
                Text("Alles bleibt auf diesem iPhone – auch deine Handschrift und Notizen. Sichere regelmäßig ein Backup in der Dateien-App: Wenn du Margin löschst, sind auch die Daten weg.")
            }
            .marginRow()

            Section("Über Margin") {
                LabeledContent("Version", value: BuildInfo.current.displayVersion)
                LabeledContent("Phase", value: "3 · Lernen")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) {
            Task { await refreshStatus() }
        }
        .onChange(of: settings.defaultTaskReminder) {
            ReminderService.scheduleRefresh(context: context)
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: BackupService.suggestedFileName()) { result in
            if case .success = result { message = "Backup gesichert." }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pendingBackup = try BackupService.decode(data)
            } catch {
                message = error.localizedDescription
            }
        }
        .alert("Backup wiederherstellen?", isPresented: restoreBinding, presenting: pendingBackup) { backup in
            Button("Ersetzen", role: .destructive) { restore(backup) }
            Button("Abbrechen", role: .cancel) {}
        } message: { backup in
            Text("Backup vom \(Fmt.date(backup.exportedAt)) mit \(backup.subjects.count) Fächern und \(backup.tasks.count) Aufgaben. Alle aktuellen Daten in Margin werden dadurch ersetzt.")
        }
        .confirmationDialog("Alle Daten löschen?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                BackupService.deleteEverything(context: context)
                ReminderService.scheduleRefresh(context: context)
                message = "Alle Daten wurden gelöscht."
            }
        } message: {
            Text("Fächer, Stundenplan, Aufgaben, Prüfungen, Termine, Anhänge, Notizen und Handschriften werden endgültig gelöscht. Sichere vorher ein Backup.")
        }
        .alert("Margin", isPresented: messageBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Erlaubt"
        case .denied: "Nicht erlaubt"
        default: "Noch nicht gefragt"
        }
    }

    private func refreshStatus() async {
        notificationStatus = await ReminderService.authorizationStatus()
    }

    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.export(context: context, settings: settings))
            showExporter = true
        } catch {
            message = "Das Backup konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }

    private func restore(_ backup: BackupFile) {
        do {
            try BackupService.restore(backup, context: context, settings: settings)
            message = "Backup wiederhergestellt."
        } catch {
            message = "Wiederherstellen fehlgeschlagen: \(error.localizedDescription)"
        }
        pendingBackup = nil
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }
}

struct SchoolDaysView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            Section {
                ForEach(1...7, id: \.self) { day in
                    Toggle(Fmt.weekdayName(day), isOn: binding(for: day))
                }
            } footer: {
                Text("Diese Tage erscheinen im Stundenplan.")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Unterrichtstage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for day: Int) -> Binding<Bool> {
        Binding(
            get: { settings.schoolDays.contains(day) },
            set: { isOn in
                if isOn {
                    settings.schoolDays = Array(Set(settings.schoolDays + [day])).sorted()
                } else if settings.schoolDays.count > 1 {
                    settings.schoolDays.removeAll { $0 == day }
                }
            }
        )
    }
}

/// The bell schedule: when each lesson period starts and ends.
struct PeriodScheduleView: View {
    @Environment(AppSettings.self) private var settings
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                ForEach($settings.periods) { $period in
                    let index = settings.periods.firstIndex { $0.id == period.id } ?? 0
                    HStack {
                        Text("\(index + 1).")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .frame(width: 30, alignment: .leading)
                        DatePicker("Beginn", selection: minuteBinding($period.startMinute), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("–")
                        DatePicker("Ende", selection: minuteBinding($period.endMinute), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                    }
                }
                .onDelete { settings.periods.remove(atOffsets: $0) }

                Button {
                    let last = settings.periods.last
                    let start = (last?.endMinute ?? 475) + 5
                    settings.periods.append(Period(startMinute: start, endMinute: start + 45))
                } label: {
                    Label("Stunde hinzufügen", systemImage: "plus")
                }
            } footer: {
                Text("Mit dem Raster trägst du Stunden schneller ein („3.–4. Stunde“). Bereits eingetragene Stunden behalten ihre Uhrzeit.")
            }
            .marginRow()

            Section {
                Button("Standardraster wiederherstellen") { confirmReset = true }
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Stundenraster")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .confirmationDialog("Standardraster wiederherstellen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Wiederherstellen", role: .destructive) { settings.periods = AppSettings.standardPeriods }
        }
    }

    private func minuteBinding(_ minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.school.date(on: .now, minute: minute.wrappedValue) },
            set: { minute.wrappedValue = Calendar.school.minuteOfDay($0) }
        )
    }
}
