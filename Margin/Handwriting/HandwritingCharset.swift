import Foundation

/// The characters a handwriting profile is built from, in capture order.
enum HandwritingCharset {
    static let lowercase = "abcdefghijklmnopqrstuvwxyzäöüß".map { String($0) }
    static let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ".map { String($0) }
    static let digits = "0123456789".map { String($0) }
    static let punctuation = [".", ",", ";", ":", "!", "?", "-", "(", ")", "„", "“", "\"", "'", "/", "+", "=", "%", "€", "&"]

    static let groups: [(title: String, characters: [String])] = [
        ("Kleinbuchstaben", lowercase),
        ("Großbuchstaben", uppercase),
        ("Ziffern", digits),
        ("Satzzeichen", punctuation),
    ]

    static let all: [String] = lowercase + uppercase + digits + punctuation

    /// The most frequent German letters. Writing extra versions of these
    /// makes repeated text look the least mechanical.
    static let variantLetters = "enisratdhulcgmo".map { String($0) }

    /// Letters that sit between baseline and x-height line (no ascender, no descender).
    static let xHeightLetters: Set<String> = Set("acemnorsuvwxz".map { String($0) })

    /// Characters whose ink ends on the baseline (no descender).
    static let baselineCharacters: Set<String> = xHeightLetters
        .union("bdhiklt".map { String($0) })
        .union("ABCDEFGHIKLMNOPRSTUVWXYZ".map { String($0) })
        .union(digits)

    static let capitalLetters: Set<String> = Set(uppercase)

    /// German pangram (contains ä, ö, ü and ß) for previews.
    static let pangram = "Zwölf Boxkämpfer jagen Viktor quer über den großen Sylter Deich."

    /// Written once to measure the natural gap between letters.
    static let sampleWord = "Handschrift"

    /// Hint shown while writing a character.
    static func hint(for character: String) -> String {
        if xHeightLetters.contains(character) { return "Von der Grundlinie bis zur gestrichelten Linie." }
        if capitalLetters.contains(character) { return "Großbuchstabe: bis zur oberen Linie." }
        if digits.contains(character) { return "Ziffer: etwa so hoch wie ein Großbuchstabe." }
        if "gjpqy".contains(character) { return "Unterlänge: unter die Grundlinie." }
        if "bdfhklt".contains(character) { return "Oberlänge: über die gestrichelte Linie." }
        if punctuation.contains(character) { return "So groß und so hoch, wie du es im Text schreibst." }
        return "Schreib so, wie du es auch im Heft schreibst."
    }
}
