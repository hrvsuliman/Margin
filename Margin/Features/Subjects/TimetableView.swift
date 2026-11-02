import SwiftData
import SwiftUI

/// The weekly timetable ("Stundenplan"), one school day at a time,
/// laid out along the bell schedule so empty periods can be filled with one tap.
struct TimetableView: View {
    @Environment(AppSettings.self) private var settings
    @Query private var lessons: [Lesson]
    @Query private var subjects: [SchoolSubject]

    @State private var weekday: Int = {
        let today = Calendar.school.isoWeekday(of: .now)
        let days = AppSettings.shared.sortedSchoolDays
        return days.contains(today) ? today : (days.first ?? 1)
    }()
    @State private var sheet: EditorSheet?

    private var dayLessons: [Lesson] {
        lessons.filter { $0.weekday == weekday }.sorted { $0.startMinute < $1.startMinute }
    }

    private func lesson(in period: Period) -> Lesson? {
        dayLessons.first { $0.startMinute < period.endMinute && $0.endMinute > period.startMinute }
    }

    /// Lessons whose times don't touch any period of the bell schedule.
    private var otherLessons: [Lesson] {
        dayLessons.filter { lesson in
            !settings.periods.contains { lesson.startMinute < $0.endMinute && lesson.endMinute > $0.startMinute }
        }
    }

    private var weeklyCount: Int {
        lessons.filter { settings.schoolDays.contains($0.weekday) }.count
    }

    var body: some View {
        List {
            Section {
                Picker("Tag", selection: $weekday) {
                    ForEach(settings.sortedSchoolDays, id: \.self) { day in
                        Text(Fmt.weekdayName(day, short: true)).tag(day)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("\(Fmt.weekdayName(weekday)) · \(dayLessons.count) Einträge · \(weeklyCount) pro Woche")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if subjects.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "books.vertical",
                        title: "Zuerst Fächer anlegen",
                        message: "Der Stundenplan besteht aus deinen Fächern.",
                        actionTitle: "Fächer auswählen",
                        action: { sheet = .subjectTemplates }
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(Array(settings.periods.enumerated()), id: \.element.id) { index, period in
                        periodRow(index: index, period: period)
                    }
                }
                .marginRow()

                if !otherLessons.isEmpty {
                    Section("Weitere Stunden") {
                        ForEach(otherLessons) { lesson in
                            Button {
                                sheet = .lesson(lesson)
                            } label: {
                                HStack {
                                    Text("\(Fmt.clock(lesson.startMinute))–\(Fmt.clock(lesson.endMinute))")
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.secondaryInk)
                                    lessonLabel(lesson)
                                }
                            }
                        }
                    }
                    .marginRow()
                }
            }
        }
        .marginList()
        .animation(.easeInOut(duration: 0.2), value: weekday)
        .navigationTitle("Stundenplan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheet = .newLesson(subject: nil, weekday: weekday, period: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Stunde hinzufügen")
                .disabled(subjects.isEmpty)
            }
        }
        .editorSheet($sheet)
    }

    private func periodRow(index: Int, period: Period) -> some View {
        Button {
            if let lesson = lesson(in: period) {
                sheet = .lesson(lesson)
            } else {
                sheet = .newLesson(subject: nil, weekday: weekday, period: index)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(index + 1).")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(Fmt.clock(period.startMinute))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.secondaryInk)
                }
                .frame(width: 40, alignment: .trailing)

                if let lesson = lesson(in: period) {
                    MarginBar(color: lesson.subject?.color.color ?? SubjectColor.gray.color)
                        .frame(height: 30)
                    lessonLabel(lesson)
                } else {
                    Text("frei")
                        .foregroundStyle(Palette.faintInk)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.footnote)
                        .foregroundStyle(Palette.faintInk)
                }
            }
        }
    }

    private func lessonLabel(_ lesson: Lesson) -> some View {
        HStack {
            Text(lesson.subject?.name ?? "Unterricht")
                .foregroundStyle(Palette.ink)
            Spacer()
            let room = lesson.room.isEmpty ? (lesson.subject?.room ?? "") : lesson.room
            if !room.isEmpty {
                Text(room)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}
