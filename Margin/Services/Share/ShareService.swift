import BackgroundTasks
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// `.margin` files: flashcard decks and notes to send to classmates
/// (AirDrop, WhatsApp, Mail …) and import with one tap.
struct ShareFile: Codable {
    static let formatName = "margin-share"

    struct Card: Codable { var front: String; var back: String }
    struct Note: Codable { var title: String; var body: String }

    var format = ShareFile.formatName
    var version = 1
    var kind: String
    var title: String
    var subject: String?
    var cards: [Card]?
    var note: Note?
}

extension UTType {
    static let marginShare = UTType(exportedAs: "com.hrvsuliman.margin.share", conformingTo: .json)
}

@MainActor
enum ShareService {
    static func deck(title: String, subject: String?, cards: [Flashcard]) throws -> URL {
        let file = ShareFile(kind: "deck", title: title, subject: subject,
                             cards: cards.map { ShareFile.Card(front: $0.front, back: $0.back) })
        return try write(file)
    }

    static func note(_ document: NoteDocument, subject: String?) throws -> URL {
        let body = document.body
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(NoteBlock.imagePrefix) }
            .joined(separator: "\n")
        let file = ShareFile(kind: "note", title: document.title.isEmpty ? "Notiz" : document.title, subject: subject,
                             note: ShareFile.Note(title: document.title, body: body))
        return try write(file)
    }

    private static func write(_ file: ShareFile) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        let safe = file.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(safe.isEmpty ? "Margin" : safe).margin")
        try data.write(to: url)
        return url
    }

    static func read(_ data: Data) -> ShareFile? {
        guard let file = try? JSONDecoder().decode(ShareFile.self, from: data), file.format == ShareFile.formatName else { return nil }
        return file
    }

    /// Imports a shared deck or note; matches the subject by name.
    @discardableResult
    static func importFile(_ file: ShareFile, context: ModelContext) -> String {
        let subjects = (try? context.fetch(FetchDescriptor<SchoolSubject>())) ?? []
        let subject = file.subject.flatMap { name in subjects.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame } }
        if let cards = file.cards, !cards.isEmpty {
            for entry in cards {
                let card = Flashcard(front: entry.front, back: entry.back)
                card.subjectUID = subject?.uid
                context.insert(card)
            }
            try? context.save()
            return "\(cards.count) Karteikarten importiert"
        }
        if let shared = file.note {
            let note = NoteDocument(title: shared.title.isEmpty ? file.title : shared.title)
            note.body = shared.body
            note.subjectUID = subject?.uid
            note.folder = "Geteilt"
            context.insert(note)
            try? context.save()
            LearningStore.syncCards(for: note, context: context)
            return "Notiz „\(note.title)“ importiert"
        }
        return "Die Datei war leer."
    }
}

/// Saves a backup into a folder the user picked once (iCloud Drive, OneDrive …),
/// at most once a day, keeping the last 7.
@MainActor
enum AutoBackup {
    private static let bookmarkKey = "backup.folderBookmark"
    private static let lastKey = "backup.lastAuto"

    static var folderName: String? {
        resolvedFolder()?.lastPathComponent
    }

    static var lastBackup: Date? {
        UserDefaults.standard.object(forKey: lastKey) as? Date
    }

    static func setFolder(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        return true
    }

    static func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private static func resolvedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Writes today's backup if there isn't one yet (or always, when `force`).
    @discardableResult
    static func runIfDue(context: ModelContext, force: Bool = false) -> Bool {
        guard let folder = resolvedFolder() else { return false }
        if !force, let last = lastBackup, Calendar.school.isDateInToday(last) { return true }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let data = try? BackupService.export(context: context, settings: AppSettings.shared) else { return false }
        let name = BackupService.suggestedFileName() + ".json"
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            return false
        }
        UserDefaults.standard.set(Date.now, forKey: lastKey)
        // Keep the newest 7 automatic backups.
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let backups = files.filter { $0.lastPathComponent.hasPrefix("Margin-Backup-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(7) { try? FileManager.default.removeItem(at: old) }
        return true
    }
}

/// Background refresh: WebUntis changes, the Claude connector and the daily backup.
enum BackgroundRefresh {
    static let identifier = "com.hrvsuliman.margin.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                let context = Persistence.container.mainContext
                await SchoolSync.shared.refreshIfNeeded(context: context, maxAge: 60 * 60)
                await ConnectorSync.shared.sync(context: context)
                AutoBackup.runIfDue(context: context)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
