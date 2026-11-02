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
    @State private var incoming: IncomingFile?

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
            switch scenePhase {
            case .active:
                Task { await ReminderService.refresh(context: context) }
                Task { await ConnectorSync.shared.sync(context: context) }
                Task { await SchoolSync.shared.refreshIfNeeded(context: context) }
                if UserDefaults.standard.bool(forKey: "intent.startFocus") { tab = .learn }
            case .background:
                AutoBackup.runIfDue(context: context)
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .onOpenURL { url in
            incoming = IncomingFile(url: url)
        }
        .sheet(item: $incoming) { file in
            InboxView(file: file) { note in
                UserDefaults.standard.set(note.uid.uuidString, forKey: "route.openNote")
                tab = .notes
            }
        }
    }
}
