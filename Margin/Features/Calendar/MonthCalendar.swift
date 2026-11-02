import SwiftUI

/// Month grid with colour dots for exams, tasks and events; the selected
/// day's entries are listed underneath.
struct MonthCalendar: View {
    @Binding var selected: Date
    let agenda: Agenda
    let open: (AgendaSource) -> Void

    @State private var month: Date = Calendar.school.dateInterval(of: .month, for: .now)?.start ?? .now
    private let calendar = Calendar.school

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayLabels
            grid
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            changeMonth(by: value.translation.width < 0 ? 1 : -1)
                        }
                )
            Rectangle()
                .fill(Palette.ruling)
                .frame(height: 1)
                .padding(.top, 6)
            DayAgendaList(day: selected, agenda: agenda, open: open)
        }
        .onAppear { syncMonth() }
        .onChange(of: selected) { syncMonth() }
    }

    private var header: some View {
        HStack {
            Text(Fmt.month(month))
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Spacer()
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 32)
            }
            .accessibilityLabel("Vorheriger Monat")
            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 32)
            }
            .accessibilityLabel("Nächster Monat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(1...7, id: \.self) { day in
                Text(Fmt.weekdayName(day, short: true))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(day >= 6 ? Palette.faintInk : Palette.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var grid: some View {
        let days = calendar.monthGrid(for: month)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { day in
                DayCell(
                    day: day,
                    inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                    isSelected: calendar.isDate(day, inSameDayAs: selected),
                    isToday: calendar.isDateInToday(day),
                    isHoliday: agenda.holiday(on: day) != nil,
                    markers: agenda.markers(on: day)
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selected = day
                    }
                    Haptics.selection()
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func changeMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            month = next
            // Keep the selection inside the visible month.
            if !calendar.isDate(selected, equalTo: next, toGranularity: .month) {
                selected = calendar.isDate(.now, equalTo: next, toGranularity: .month)
                    ? calendar.startOfDay(for: .now) : next
            }
        }
        Haptics.selection()
    }

    private func syncMonth() {
        if let start = calendar.dateInterval(of: .month, for: selected)?.start, start != month {
            month = start
        }
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isHoliday: Bool
    let markers: [Color]

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.school.component(.day, from: day))")
                .font(.callout.weight(isToday || isSelected ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(numberColor)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(Palette.ink)
                    } else if isToday {
                        Circle().stroke(Palette.marginRed, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 3) {
                ForEach(Array(markers.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background {
            if isHoliday && inMonth {
                RoundedRectangle(cornerRadius: 8).fill(Palette.ruling.opacity(0.45))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var numberColor: Color {
        if isSelected { return Palette.paper }
        if isToday { return Palette.marginRed }
        return inMonth ? Palette.ink : Palette.faintInk
    }

    private var accessibilityText: String {
        var text = Fmt.longDay(day)
        if isHoliday { text += ", schulfrei" }
        if !markers.isEmpty { text += ", \(markers.count) Einträge" }
        return text
    }
}
