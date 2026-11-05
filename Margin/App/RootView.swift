import CoreSpotlight
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
    @State private var routedSheet: EditorSheet?
    @State private var routedSubject: SchoolSubject?

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
                Task { await CalendarSync.shared.sync(context: context) }
                SpotlightIndex.scheduleRefresh(context: context)
                if UserDefaults.standard.bool(forKey: "intent.startFocus") { tab = .learn }
            case .background:
                WidgetBridge.refresh(context: context)
                AutoBackup.runIfDue(context: context)
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .onOpenURL { url in
            if let route = AppRoute(url: url) {
                go(route)
            } else if url.scheme == "margin" {
                tab = .today
            } else {
                incoming = IncomingFile(url: url)
            }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let route = AppRoute(identifier: id) {
                go(route)
            }
        }
        .editorSheet($routedSheet)
        .sheet(item: $routedSubject) { subject in
            NavigationStack {
                SubjectDetailView(subject: subject)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fertig") { routedSubject = nil }
                        }
                    }
            }
            .tint(Palette.marginRed)
        }
        .sheet(item: $incoming) { file in
            InboxView(file: file) { note in
                UserDefaults.standard.set(note.uid.uuidString, forKey: "route.openNote")
                tab = .notes
            }
        }
    }

    /// Opens what a search result, widget or link points to.
    private func go(_ route: AppRoute) {
        switch route {
        case .today:
            tab = .today
        case .note(let id):
            UserDefaults.standard.set(id.uuidString, forKey: "route.openNote")
            tab = .notes
        case .task(let id):
            if let task = ((try? context.fetch(FetchDescriptor<SchoolTask>())) ?? []).first(where: { $0.uid == id }) {
                routedSheet = .task(task)
            }
        case .exam(let id):
            if let exam = ((try? context.fetch(FetchDescriptor<Exam>())) ?? []).first(where: { $0.uid == id }) {
                routedSheet = .exam(exam)
            }
        case .subject(let id):
            routedSubject = ((try? context.fetch(FetchDescriptor<SchoolSubject>())) ?? []).first { $0.uid == id }
        }
    }
}
