import SwiftUI

/// Calendar and task list share one tab; a switch in the navigation bar flips between them.
struct PlannerView: View {
    @AppStorage("planner.mode") private var mode = PlannerSwitch.calendar

    var body: some View {
        if mode == PlannerSwitch.tasks {
            TasksView(plannerMode: $mode)
        } else {
            CalendarScreen(plannerMode: $mode)
        }
    }
}

struct PlannerSwitch: View {
    static let calendar = "calendar"
    static let tasks = "tasks"

    @Binding var mode: String

    var body: some View {
        Picker("Ansicht", selection: $mode) {
            Text("Kalender").tag(Self.calendar)
            Text("Aufgaben").tag(Self.tasks)
        }
        .pickerStyle(.segmented)
        .frame(width: 210)
        .onChange(of: mode) { Haptics.selection() }
    }
}
