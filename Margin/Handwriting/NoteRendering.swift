import Foundation
import SwiftData

/// Connects stored notes and profiles to the layout engine.
/// Values are read on the main thread; the heavy work runs in the background.
@MainActor
enum NoteRendering {
    static func profile(for document: NoteDocument, in profiles: [HandwritingProfile]) -> HandwritingProfile? {
        if let uid = document.profileUID, let match = profiles.first(where: { $0.uid == uid }) {
            return match
        }
        return defaultProfile(in: profiles)
    }

    static func defaultProfile(in profiles: [HandwritingProfile]) -> HandwritingProfile? {
        profiles.first(where: \.isDefault) ?? profiles.sorted { $0.createdAt < $1.createdAt }.first
    }

    static func header(for document: NoteDocument, subjects: [SchoolSubject]) -> String {
        let subject = document.subjectUID.flatMap { uid in subjects.first { $0.uid == uid }?.name }
        return [subject, Fmt.date(document.noteDate)].compactMap { $0 }.joined(separator: " · ")
    }

    static func content(for document: NoteDocument, subjects: [SchoolSubject]) -> NoteContent {
        NoteContent(
            title: document.title,
            header: header(for: document, subjects: subjects),
            body: document.body,
            seed: UInt64(bitPattern: Int64(document.seed))
        )
    }

    static func render(content: NoteContent, settings: PageSettings, source: FontSource) async -> [LaidOutPage] {
        await Task.detached(priority: .userInitiated) {
            let font = HandwritingFont(source: source, penRatio: settings.penRatio)
            return NoteLayout.layout(content, settings: settings, font: font)
        }.value
    }

    /// Renders a document completely and returns the PDF.
    static func pdf(for document: NoteDocument, subjects: [SchoolSubject], profiles: [HandwritingProfile]) async -> Data {
        let noteContent = Self.content(for: document, subjects: subjects)
        let settings = PageSettings(document: document)
        let source = Self.profile(for: document, in: profiles).map { FontSource(profile: $0) } ?? .empty
        let title = document.title.isEmpty ? "Notiz" : document.title
        return await Task.detached(priority: .userInitiated) {
            let font = HandwritingFont(source: source, penRatio: settings.penRatio)
            let pages = NoteLayout.layout(noteContent, settings: settings, font: font)
            return PageRenderer.pdf(pages: pages, settings: settings, title: title)
        }.value
    }

    /// Writes PDF data to a temporary file with a readable name, for sharing.
    static func temporaryPDF(_ data: Data, title: String) throws -> URL {
        let safe = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent((safe.isEmpty ? "Notiz" : safe) + ".pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
