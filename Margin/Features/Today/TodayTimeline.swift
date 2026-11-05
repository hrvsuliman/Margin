import SwiftData
import SwiftUI

/// The day as a timeline: lessons, breaks, study blocks and appointments, with a "now" line.
enum DayPlan {
    enum Row: Identifiable {
        case item(AgendaItem)
        case pause(start: Date, minutes: Int)
        case now(Date)
        case schoolOut(Date)

        var id: String {
            switch self {
            case .item(let item): "item-\(item.id)"
            case .pause(let start, _): "pause-\(start.timeIntervalSince1970)"
            case .now: "now"
            case .schoolOut: "out"
            }
        }
    }

    /// Breaks between lessons are shown when they are 5 to 90 minutes long.
    static func rows(items: [AgendaItem], now: Date, isToday: Bool) -> [Row] {
        let timed = items.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let lastLesson = timed.last(where: \.isLesson)
        var rows: [Row] = []
        var placedNow = !isToday || timed.contains { $0.start <= now && now < $0.end }

        for (index, item) in timed.enumerated() {
            if !placedNow, now < item.start {
                rows.append(.now(now))
                placedNow = true
            }
            rows.append(.item(item))
            if item.isLesson, index + 1 < timed.count, timed[index + 1].isLesson {
                let minutes = Int(timed[index + 1].start.timeIntervalSince(item.end) / 60)
                if (5...90).contains(minutes) { rows.append(.pause(start: item.end, minutes: minutes)) }
            }
            if let lastLesson, item.id == lastLesson.id {
                rows.append(.schoolOut(item.end))
            }
        }
        if !placedNow, !timed.isEmpty { rows.append(.now(now)) }
        return rows
    }

    /// The subject behind a lesson or a WebUntis entry.
    @MainActor
    static func subject(of item: AgendaItem, in subjects: [SchoolSubject]) -> SchoolSubject? {
        switch item.source {
        case .lesson(let lesson): lesson.subject
        case .entry(let entry): entry.subjectUID.flatMap { id in subjects.first { $0.uid == id } }
        case .session(let session): session.subjectUID.flatMap { id in subjects.first { $0.uid == id } }
        default: nil
        }
    }
}

/// One row of the day timeline: time, a rail with a dot, and the item.
struct TimelineRowView: View {
    let row: DayPlan.Row
    let now: Date
    var badges: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isNowRow ? Palette.marginRed : Palette.secondaryInk)
                .frame(width: 40, alignment: .trailing)
                .padding(.top, 11)
            rail
            content
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isPast ? 0.45 : 1)
    }

    private var isNowRow: Bool {
        if case .now = row { return true }
        return false
    }

    private var isPast: Bool {
        if case .item(let item) = row { return item.end <= now }
        if case .pause(let start, let minutes) = row { return start.addingTimeInterval(Double(minutes) * 60) <= now }
        return false
    }

    private var isCurrent: Bool {
        if case .item(let item) = row { return item.start <= now && now < item.end }
        return false
    }

    private var time: String {
        switch row {
        case .item(let item): Fmt.time(item.start)
        case .pause: ""
        case .now(let date): Fmt.time(date)
        case .schoolOut(let date): Fmt.time(date)
        }
    }

    private var dotColor: Color {
        switch row {
        case .item(let item): item.color
        case .now: Palette.marginRed
        default: Palette.ruling
        }
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Palette.ruling)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            switch row {
            case .item:
                Circle()
                    .fill(isCurrent ? dotColor : Palette.paper)
                    .overlay(Circle().stroke(dotColor, lineWidth: 2))
                    .frame(width: 11, height: 11)
                    .padding(.top, 13)
            case .now:
                Circle().fill(Palette.marginRed).frame(width: 9, height: 9).padding(.top, 14)
            case .schoolOut:
                Image(systemName: "flag.checkered")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(3)
                    .background(Palette.paper, in: Circle())
                    .padding(.top, 9)
            case .pause:
                EmptyView()
            }
        }
        .frame(width: 14)
    }

    @ViewBuilder
    private var content: some View {
        switch row {
        case .item(let item):
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: item.symbol)
                        .font(.caption)
                        .foregroundStyle(item.color)
                    Text(item.title)
                        .font(isCurrent ? .headline : .body)
                        .foregroundStyle(Palette.ink)
                        .strikethrough(item.isDone && item.isLesson, color: Palette.secondaryInk)
                        .lineLimit(1)
                }
                let detail = [item.detail, isCurrent ? "noch \(Int(item.end.timeIntervalSince(now) / 60) + 1) Min." : ""]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(item.isChange ? Palette.marginRed : Palette.secondaryInk)
                        .lineLimit(2)
                }
                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.marginRed)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.marginRed.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, isCurrent ? 10 : 0)
            .padding(.vertical, isCurrent ? 6 : 0)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 10).fill(item.color.opacity(0.1))
                }
            }
        case .pause(_, let minutes):
            Text("Pause · \(minutes) Min.")
                .font(.caption)
                .foregroundStyle(Palette.faintInk)
        case .now:
            HStack(spacing: 6) {
                Text("Jetzt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.marginRed)
                Rectangle().fill(Palette.marginRed.opacity(0.5)).frame(height: 1)
            }
            .padding(.top, 4)
        case .schoolOut:
            Text("Schulschluss")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

/// The lesson happening now or next, large, with a live countdown.
struct NowCard: View {
    let item: AgendaItem
    let subject: SchoolSubject?
    let now: Date
    var badges: [String] = []

    private var isNow: Bool { item.start <= now && now < item.end }

    var body: some View {
        HStack(spacing: 14) {
            MarginBar(color: item.color, width: 5)
                .frame(height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(isNow ? "JETZT" : "ALS NÄCHSTES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(item.color)
                Text(item.title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text([Fmt.time(item.start) + "–" + Fmt.time(item.end), item.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(item.isChange ? Palette.marginRed : Palette.secondaryInk)
                    .lineLimit(1)
                if !badges.isEmpty {
                    Text(badges.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.marginRed)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 2) {
                let minutes = Int((isNow ? item.end : item.start).timeIntervalSince(now) / 60) + 1
                Text(minutes >= 60 ? "\(minutes / 60):\(String(format: "%02d", minutes % 60))" : "\(minutes)")
                    .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text(minutes >= 60 ? "Std." : "Min.")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
                Text(isNow ? "übrig" : "bis Beginn")
                    .font(.caption2)
                    .foregroundStyle(Palette.faintInk)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Evening preview of the next school day: start, what to pack, what is due.
struct TomorrowCard: View {
    let day: Date
    let lessons: [AgendaItem]
    let subjects: [SchoolSubject]
    let dueCount: Int
    let exams: [Exam]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.relativeDay(day, from: now).capitalized)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let first = lessons.first {
                    Text("Beginn \(Fmt.time(first.start))")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            let pack = packing
            if !pack.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Einpacken")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                    FlowChips(items: pack.map { ($0.name, $0.color.color) })
                }
            }
            HStack(spacing: 14) {
                if dueCount > 0 {
                    Label("\(dueCount) Aufgabe\(dueCount == 1 ? "" : "n") fällig", systemImage: "checklist")
                }
                ForEach(exams) { exam in
                    Label(exam.displayTitle, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Palette.marginRed)
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
        .padding(.vertical, 4)
    }

    /// Each subject once, in timetable order, without cancelled lessons.
    private var packing: [SchoolSubject] {
        var seen = Set<UUID>()
        return lessons.filter { !$0.isDone }.compactMap { DayPlan.subject(of: $0, in: subjects) }
            .filter { seen.insert($0.uid).inserted }
    }
}

/// Small coloured name chips that wrap onto new lines.
struct FlowChips: View {
    let items: [(String, Color)]

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Circle().fill(item.1).frame(width: 7, height: 7)
                    Text(item.0).font(.footnote)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Palette.sheet, in: Capsule())
            }
        }
    }
}

/// Lays children out left to right and wraps like text.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
