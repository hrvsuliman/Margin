import SwiftUI

/// The week as a list of days. Lessons are summarised in one line per day,
/// so exams, tasks and events stand out.
struct WeekCalendar: View {
    @Binding var selected: Date
    let agenda: Agenda
    let open: (AgendaSource) -> Void
    let showDay: (Date) -> Void

    private let calendar = Calendar.school

    private var weekStart: Date { calendar.startOfWeek(for: selected) }
    private var days: [Date] { (0..<7).map { calendar.addingDays($0, to: weekStart) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(days, id: \.self) { day in
                    daySection(day)
                }
            }
            .marginList()
        }
    }

    private var header: some View {
        let end = calendar.addingDays(6, to: weekStart)
        let week = calendar.component(.weekOfYear, from: weekStart)
        return HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("KW \(week)")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(Fmt.dayMonth(weekStart)) – \(Fmt.dayMonth(end))")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
            Spacer()
            Button { move(by: -7) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 32)
            }
            .accessibilityLabel("Vorherige Woche")
            Button { move(by: 7) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 32)
            }
            .accessibilityLabel("Nächste Woche")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                move(by: value.translation.width < 0 ? 7 : -7)
            }
        )
    }

    private func daySection(_ day: Date) -> some View {
        let items = agenda.items(on: day)
        let lessons = items.filter(\.isLesson)
        let others = items.filter { !$0.isLesson }
        let isToday = calendar.isDateInToday(day)

        return Section {
            if !lessons.isEmpty {
                Button {
                    showDay(day)
                } label: {
                    lessonSummary(lessons)
                }
            }
            ForEach(others) { item in
                Button {
                    open(item.source)
                } label: {
                    AgendaRow(item: item)
                }
            }
            if items.isEmpty {
                Text("Frei")
                    .font(.subheadline)
                    .foregroundStyle(Palette.faintInk)
            }
        } header: {
            Button {
                showDay(day)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.weekday(day))
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(isToday ? Palette.marginRed : Palette.ink)
                    Text(Fmt.dayMonth(day))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer()
                }
            }
            .textCase(nil)
        }
        .marginRow()
    }

    private func lessonSummary(_ lessons: [AgendaItem]) -> some View {
        HStack(spacing: 12) {
            Text("\(lessons.count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .frame(width: 46, alignment: .trailing)
            HStack(spacing: 3) {
                ForEach(lessons) { item in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(item.color)
                        .frame(width: 6, height: 18)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Stunde\(lessons.count == 1 ? "" : "n")")
                    .foregroundStyle(Palette.ink)
                if let first = lessons.first, let last = lessons.last {
                    Text("\(Fmt.time(first.start))–\(Fmt.time(last.end))")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func move(by days: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selected = calendar.addingDays(days, to: selected)
        }
        Haptics.selection()
    }
}
