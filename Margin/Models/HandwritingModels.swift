import Foundation
import SwiftData

/// A person's handwriting: the written samples of each character plus spacing settings.
@Model
final class HandwritingProfile {
    var uid: UUID = UUID()
    var name: String = ""
    var isDefault: Bool = false
    var createdAt: Date = Date.now
    /// Bumped on every change, so previews know when to re-render.
    var updatedAt: Date = Date.now

    /// Gap between letters, in x-heights. Measured from the sample word, adjustable.
    var letterSpacing: Double = 0.14
    /// Gap between words, in x-heights.
    var wordSpacing: Double = 0.75
    /// Extra slant in degrees on top of the natural slant (positive leans right).
    var slantAdjust: Double = 0
    /// How much natural variation to add (0 = none, 1 = normal, 2 = strong).
    var variation: Double = 1
    /// True once the sample word was written and spacing was measured.
    var spacingMeasured: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \GlyphSample.profile)
    var glyphs: [GlyphSample]? = []

    init(name: String) {
        self.uid = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }

    func touch() {
        updatedAt = .now
    }

    func samples(for character: String) -> [GlyphSample] {
        (glyphs ?? []).filter { $0.character == character }.sorted { $0.createdAt < $1.createdAt }
    }

    var capturedCharacters: Set<String> {
        Set((glyphs ?? []).map(\.character))
    }
}

/// One written version of one character. The strokes are stored normalised:
/// baseline at y = 0, x-height line at y = −1, ink starting at x = 0.
@Model
final class GlyphSample {
    var uid: UUID = UUID()
    var character: String = ""
    var strokeData: Data = Data()
    var createdAt: Date = Date.now
    /// Manual corrections from the character editor.
    var scale: Double = 1
    var baselineOffset: Double = 0

    var profile: HandwritingProfile?

    init(character: String, strokeData: Data) {
        self.uid = UUID()
        self.character = character
        self.strokeData = strokeData
        self.createdAt = .now
    }
}

enum PaperStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case lined, squared, dotted, blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lined: "Liniert"
        case .squared: "Kariert"
        case .dotted: "Gepunktet"
        case .blank: "Blanko"
        }
    }

    var symbol: String {
        switch self {
        case .lined: "line.3.horizontal"
        case .squared: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        case .blank: "doc"
        }
    }

    /// Typical line pitch in millimetres.
    var defaultLineSpacing: Double {
        switch self {
        case .lined: 8
        case .squared, .dotted: 10
        case .blank: 9
        }
    }
}

enum PenColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case royalBlue, black, navy, green, red, violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .royalBlue: "Königsblau"
        case .black: "Schwarz"
        case .navy: "Dunkelblau"
        case .green: "Grün"
        case .red: "Rot"
        case .violet: "Lila"
        }
    }

    var hex: UInt32 {
        switch self {
        case .royalBlue: 0x1F3FA0
        case .black: 0x1E1E22
        case .navy: 0x17264F
        case .green: 0x1F6B45
        case .red: 0xB3261E
        case .violet: 0x5B3A8C
        }
    }
}

/// A handwritten note. The text and its structure are the source of truth;
/// the handwritten pages are always re-rendered from them.
@Model
final class NoteDocument {
    var uid: UUID = UUID()
    var title: String = ""
    /// Plain text with light markup: "# " heading, "## " subheading, "- " list item.
    var body: String = ""
    var folder: String = ""
    var noteDate: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Links are stored as ids (not relationships), so deleting a subject
    // never deletes or breaks a note.
    var subjectUID: UUID?
    var topicUID: UUID?
    var examUID: UUID?
    var profileUID: UUID?

    // Page layout
    var paperRaw: String = PaperStyle.lined.rawValue
    var lineSpacingMM: Double = 8
    var writingSize: Double = 1
    var penColorRaw: String = PenColor.royalBlue.rawValue
    var penWeight: Double = 1
    var marginTopMM: Double = 20
    var marginBottomMM: Double = 15
    var marginLeftMM: Double = 20
    var marginRightMM: Double = 15
    var showMarginLine: Bool = true
    var showPageNumbers: Bool = true
    var showHeader: Bool = true
    var printPaper: Bool = true
    /// Seed for the natural variation. "Neu mischen" picks a new one.
    var seed: Int = 1

    @Attribute(.externalStorage) var thumbnail: Data?

    init(title: String) {
        self.uid = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.noteDate = .now
        self.seed = Int.random(in: 1...999_999)
    }

    var paper: PaperStyle {
        get { PaperStyle(rawValue: paperRaw) ?? .lined }
        set { paperRaw = newValue.rawValue }
    }

    var penColor: PenColor {
        get { PenColor(rawValue: penColorRaw) ?? .royalBlue }
        set { penColorRaw = newValue.rawValue }
    }
}
