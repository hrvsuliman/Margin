import SwiftUI

/// One day as a timeline: all-day entries on top, lessons and timed events
/// placed by time below, with a red line for "now".
struct DayCalendar: View {
    @Binding var selected: Date
    let agenda: Agenda
    let open: (AgendaSource) -> Void

    private let calendar = Calendar.school
    private let hourHeight: CGFloat = 58
    private let firstHour = 6
    private let lastHour = 23
    private let labelWidth: CGFloat = 48

    var body: some View {
        let items = agenda.items(on: selected)
        let allDay = items.filter(\.isAllDay)
        let timed = items.filter { !$0.isAllDay }

        VStack(spacing: 0) {
            WeekStrip(selected: $selected)
            if !allDay.isEmpty {
                VStack(spacing: 6) {
                    ForEach(allDay) { item in
                        Button {
                            open(item.source)
                        } label: {
                            AllDayChip(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Rectangle().fill(Palette.ruling).frame(height: 1)
            timeline(timed)
        }
    }

    private func timeline(_ items: [AgendaItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    GeometryReader { geometry in
                        blocks(items, width: geometry.size.width)
                        if calendar.isDateInToday(selected) {
                            nowLine(width: geometry.size.width)
                        }
                    }
                }
                .frame(height: CGFloat(lastHour - firstHour) * hourHeight + 12)
                .padding(.top, 8)
            }
            .onAppear { scrollToStart(proxy, items: items) }
            .onChange(of: selected) { scrollToStart(proxy, items: items) }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(firstHour..<lastHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(String(format: "%02d:00", hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: labelWidth - 6, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Palette.ruling)
                        .frame(height: 0.75)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func y(for date: Date) -> CGFloat {
        let minutes = calendar.minuteOfDay(date) - firstHour * 60
        let clamped = min(max(minutes, 0), (lastHour - firstHour) * 60)
        return CGFloat(clamped) / 60 * hourHeight
    }

    private func blocks(_ items: [AgendaItem], width: CGFloat) -> some View {
        let ranges = items.map { item in
            (start: Double(y(for: item.start)), end: Double(max(y(for: item.end), y(for: item.start) + 22)))
        }
        let placements = TimelineLayout.place(ranges)
        let available = max(width - labelWidth - 8, 40)

        return ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let placement = placements[index]
            let columnWidth = available / CGFloat(placement.columnCount)
            let height = CGFloat(ranges[index].end - ranges[index].start) - 2
            Button {
                open(item.source)
            } label: {
                TimelineBlock(item: item, compact: height < 40)
            }
            .buttonStyle(.plain)
            .frame(width: columnWidth - 3, height: max(height, 20))
            .offset(x: labelWidth + CGFloat(placement.column) * columnWidth, y: CGFloat(ranges[index].start) + 1)
        }
    }

    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            let yPosition = y(for: context.date)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Palette.marginRed)
                    .frame(width: width - labelWidth + 4, height: 1.5)
                    .offset(x: labelWidth - 4)
                Circle()
                    .fill(Palette.marginRed)
                    .frame(width: 8, height: 8)
                    .offset(x: labelWidth - 8)
            }
            .offset(y: yPosition - 4)
            .accessibilityHidden(true)
        }
    }

    private func scrollToStart(_ proxy: ScrollViewProxy, items: [AgendaItem]) {
        let hour: Int
        if calendar.isDateInToday(selected) {
            hour = calendar.component(.hour, from: .now) - 1
        } else if let first = items.first {
            hour = calendar.component(.hour, from: first.start)
        } else {
            hour = 7
        }
        proxy.scrollTo(min(max(hour, firstHour), lastHour - 1), anchor: .top)
    }
}

private struct TimelineBlock: View {
    let item: AgendaItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(item.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(compact ? 1 : 2)
                if !compact && !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(item.color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(Fmt.time(item.start)) bis \(Fmt.time(item.end))")
    }
}

private struct AllDayChip: View {
    let item: AgendaItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbol)
                .font(.caption)
                .foregroundStyle(item.color)
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(item.isDone ? Palette.secondaryInk : Palette.ink)
                .strikethrough(item.isDone, color: Palette.secondaryInk)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(item.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Monday to Sunday of the selected week; tap a day to jump to it.
struct WeekStrip: View {
    @Binding var selected: Date
    private let calendar = Calendar.school

    var body: some View {
        let start = calendar.startOfWeek(for: selected)
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = calendar.addingDays(offset, to: start)
                    let isSelected = calendar.isDate(day, inSameDayAs: selected)
                    let isToday = calendar.isDateInToday(day)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = day }
                        Haptics.selection()
                    } label: {
                        VStack(spacing: 4) {
                            Text(Fmt.weekdayName(offset + 1, short: true))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.secondaryInk)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.callout.weight(isSelected ? .semibold : .regular).monospacedDigit())
                                .foregroundStyle(isSelected ? Palette.paper : (isToday ? Palette.marginRed : Palette.ink))
                                .frame(width: 32, height: 32)
                                .background {
                                    if isSelected { Circle().fill(Palette.ink) }
                                }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Fmt.longDay(day))
                }
            }
            Text(Fmt.longDay(selected))
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selected = calendar.addingDays(value.translation.width < 0 ? 7 : -7, to: selected)
                }
                Haptics.selection()
            }
        )
    }
}
