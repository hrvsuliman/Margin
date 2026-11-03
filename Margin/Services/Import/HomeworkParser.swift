import Foundation

/// A task Margin suggests from a photo of the board or homework book.
/// Always shown in the task editor first, so nothing is saved without a look.
struct HomeworkSuggestion: Identifiable {
    let id = UUID()
    var title: String
    var details: String
    var dueDate: Date?
    var subjectName: String?
    var photo: Data?
}

/// Reads recognised text like "Mathe: S. 34 Nr. 5a bis Freitag" and guesses
/// title, subject and due date. Plain rules, no AI, works offline.
enum HomeworkParser {
    private static let weekdays = ["sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4,
                                   "donnerstag": 5, "freitag": 6, "samstag": 7]
    private static let taskWords = #"(?i)(\bS\.\s?\d|\bSeite\b|\bNr\.|\bAufgabe|\bAB\b|Arbeitsblatt|\bBuch\b|\bHeft\b|lernen\b|lesen\b|schreiben\b|Vokabeln|bearbeiten)"#

    static func suggest(from text: String, subjects: [String], today: Date = .now,
                        calendar: Calendar = .school) -> HomeworkSuggestion {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let titleLine = lines.first { $0.range(of: taskWords, options: .regularExpression) != nil } ?? lines.first ?? ""
        return HomeworkSuggestion(
            title: cleanTitle(titleLine),
            details: String(lines.joined(separator: "\n").prefix(1000)),
            dueDate: dueDate(in: text, today: today, calendar: calendar),
            subjectName: subject(in: text, subjects: subjects)
        )
    }

    static func cleanTitle(_ line: String) -> String {
        var title = line
        for prefix in ["Hausaufgaben:", "Hausaufgabe:", "HA:", "HA "] where title.lowercased().hasPrefix(prefix.lowercased()) {
            title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard title.count > 70 else { return title }
        let cut = title.prefix(70)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + " …"
    }

    /// Explicit date first ("bis 12.11."), then a weekday ("bis Freitag"),
    /// then "übermorgen", "morgen", "nächste Woche".
    static func dueDate(in text: String, today: Date, calendar: Calendar) -> Date? {
        let lower = text.lowercased()
        let start = calendar.startOfDay(for: today)

        if let match = lower.firstMatch(of: #/(\d{1,2})\.(\d{1,2})\.(\d{2,4})?/#),
           let day = Int(match.1), let month = Int(match.2), (1...31).contains(day), (1...12).contains(month) {
            var components = calendar.dateComponents([.year], from: start)
            components.day = day
            components.month = month
            if let year = match.3.flatMap({ Int($0) }) {
                components.year = year < 100 ? 2000 + year : year
            }
            if var date = calendar.date(from: components) {
                if match.3 == nil, date < start, let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
                if date >= start { return date }
            }
        }

        let names = weekdays.keys.joined(separator: "|")
        if let regex = try? Regex(#"(?:bis|zum|zur|für|fuer|am)\s+(?:(?:den|nächsten|naechsten|kommenden)\s+)?("# + names + ")"),
           let match = lower.firstMatch(of: regex),
           let name = match.output[1].substring.map(String.init),
           let weekday = weekdays[name] {
            return calendar.nextDate(after: start, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)
        }
        if lower.contains("übermorgen") || lower.contains("uebermorgen") {
            return calendar.date(byAdding: .day, value: 2, to: start)
        }
        if lower.firstMatch(of: #/\bmorgen\b/#) != nil {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        if lower.contains("nächste woche") || lower.contains("naechste woche") {
            return calendar.date(byAdding: .day, value: 7, to: start)
        }
        return nil
    }

    /// A subject named in the text, also by a short form ("Mathe" → "Mathematik").
    static func subject(in text: String, subjects: [String]) -> String? {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 }
        return subjects.first { subject in
            let name = subject.lowercased()
            return text.lowercased().contains(name) || words.contains { name.hasPrefix($0) }
        }
    }
}
