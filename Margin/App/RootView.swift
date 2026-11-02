import SwiftData
import SwiftUI

struct RootView: View {
    enum AppTab: Hashable {
        case today, planner, learn, notes, tutor
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
            PlannerView()
                .tabItem { Label("Planer", systemImage: "calendar") }
                .tag(AppTab.planner)
            LearnView()
                .tabItem { Label("Lernen", systemImage: "brain.head.profile") }
                .tag(AppTab.learn)
            NotesView()
                .tabItem { Label("Notizen", systemImage: "pencil.and.outline") }
                .tag(AppTab.notes)
            TutorView()
                .tabItem { Label("Tutor", systemImage: "sparkles") }
                .tag(AppTab.tutor)
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
                Task { await ConnectorSync.shared.sync(context: context) }
            }
        }
    }
}
