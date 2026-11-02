import Foundation
import SwiftData

/// Builds a "Lernzettel" (revision sheet) from what's already in the app:
/// a topic's notes, its subtopics and its flashcards. The result is a normal
/// note, so it appears in the user's handwriting and can be edited and printed.
@MainActor
enum StudySheet {
    static func body(for topics: [Topic], cards: [Flashcard], heading: String?) -> String {
        var lines: [String] = []
        if let heading { lines.append("# \(heading)") }
        for topic in topics {
            append(topic, depth: 0, cards: cards, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func append(_ topic: Topic, depth: Int, cards: [Flashcard], to lines: inout [String]) {
        if !lines.isEmpty { lines.append("") }
        lines.append(depth == 0 ? "## \(topic.title)" : "- \(topic.title)")
        let details = topic.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty {
            lines.append(contentsOf: details.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        // "Begriff: Erklärung" (single colon) so the sheet doesn't create duplicate cards.
        for card in cards where card.topicUID == topic.uid {
            lines.append("- \(card.front): \(card.back)")
        }
        for child in topic.sortedChildren {
            append(child, depth: depth + 1, cards: cards, to: &lines)
        }
    }

    /// Creates the note and returns it.
    static func create(for topics: [Topic], title: String, subject: SchoolSubject?, context: ModelContext) -> NoteDocument {
        let cards = (try? context.fetch(FetchDescriptor<Flashcard>())) ?? []
        let note = NoteDocument(title: "Lernzettel: \(title)")
        note.body = body(for: topics, cards: cards, heading: nil)
        note.subjectUID = subject?.uid
        note.topicUID = topics.count == 1 ? topics.first?.uid : nil
        note.folder = "Lernzettel"
        context.insert(note)
        try? context.save()
        return note
    }
}
