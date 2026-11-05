import SwiftData
import SwiftUI

/// Apple Calendar sync and iPhone search.
struct IntegrationSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var calendar = CalendarSync.shared
    @State private var spotlight = SpotlightIndex.isEnabled
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Toggle("Im Kalender anzeigen", isOn: Binding(
                    get: { calendar.isEnabled },
                    set: { on in
                        if on {
                            working = true
                            Task {
                                await calendar.enable(context: context)
                                working = false
                            }
                        } else {
                            calendar.disable()
                        }
                    }
                ))
                .disabled(working)
                if calendar.isEnabled {
                    Toggle("Aufgaben mit Datum", isOn: $calendar.includeTasks)
                    Toggle("Geplante Lerneinheiten", isOn: $calendar.includeSessions)
                    if let last = calendar.lastSync {
                        LabeledContent("Zuletzt abgeglichen", value: Fmt.time(last))
                    }
                }
                if let error = calendar.lastError {
                    Text(error).font(.footnote).foregroundStyle(Palette.marginRed)
                }
            } header: {
                Text("Apple Kalender")
            } footer: {
                Text("Prüfungen, Aufgaben und Lerneinheiten erscheinen in einem eigenen Kalender „Margin“ in der Kalender-App (und auf der Apple Watch). Änderungen machst du in Margin – sie werden automatisch übernommen. Andere Kalender liest oder ändert Margin nicht. Ausschalten löscht den Kalender „Margin“ wieder.")
            }
            .marginRow()
            .onChange(of: calendar.includeTasks) { Task { await calendar.sync(context: context) } }
            .onChange(of: calendar.includeSessions) { Task { await calendar.sync(context: context) } }

            Section {
                Toggle("In der iPhone-Suche zeigen", isOn: $spotlight)
                    .onChange(of: spotlight) {
                        SpotlightIndex.isEnabled = spotlight
                        if spotlight { Task { await SpotlightIndex.refresh(context: context) } }
                    }
            } header: {
                Text("iPhone-Suche")
            } footer: {
                Text("Notizen, offene Aufgaben, Prüfungen und Fächer findest du auch, wenn du auf dem Home-Bildschirm nach unten wischst. Der Suchindex bleibt auf dem iPhone.")
            }
            .marginRow()
        }
        .marginList()
        .navigationTitle("Kalender und Suche")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if working { ProgressView() }
        }
    }
}
