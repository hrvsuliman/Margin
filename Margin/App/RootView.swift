import SwiftData
import SwiftUI

struct RootView: View {
    enum AppTab: Hashable {
        case today, calendar, subjects, tasks, notes
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today
    @State private var didLaunch = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Heute", systemImage: "sun.max") }
                .tag(AppTab.today)
            CalendarScreen()
                .tabItem { Label("Kalender", systemImage: "calendar") }
                .tag(AppTab.calendar)
            SubjectsView()
                .tabItem { Label("Fächer", systemImage: "books.vertical") }
                .tag(AppTab.subjects)
            TasksView()
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
                .tag(AppTab.tasks)
            NotesView()
                .tabItem { Label("Notizen", systemImage: "pencil.and.outline") }
                .tag(AppTab.notes)
        }
        .onChange(of: tab) { Haptics.selection() }
        .onAppear {
            guard !didLaunch else { return }
            didLaunch = true
            AttachmentStore.removeOrphanedFiles(context: context)
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                Task { await ReminderService.refresh(context: context) }
            }
        }
    }
}
