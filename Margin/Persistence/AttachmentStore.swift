import Foundation
import SwiftData

/// Stores attachment files in Application Support/Attachments.
/// The database only keeps the file name, the bytes live here.
@MainActor
enum AttachmentStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for attachment: Attachment) -> URL {
        directory.appendingPathComponent(attachment.storedName)
    }

    /// Copies a file the user picked (Files app) into the app.
    static func importFile(at source: URL) throws -> Attachment {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        return try store(data, fileName: source.lastPathComponent)
    }

    /// Saves raw data (e.g. a photo) as a new attachment. Not yet inserted into a context.
    static func store(_ data: Data, fileName: String) throws -> Attachment {
        let ext = (fileName as NSString).pathExtension
        let storedName = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        try data.write(to: directory.appendingPathComponent(storedName), options: .atomic)
        return Attachment(fileName: fileName, storedName: storedName, byteCount: data.count)
    }

    static func data(for attachment: Attachment) -> Data? {
        try? Data(contentsOf: url(for: attachment))
    }

    /// Deletes the attachment and its file.
    static func delete(_ attachment: Attachment, context: ModelContext) {
        try? FileManager.default.removeItem(at: url(for: attachment))
        context.delete(attachment)
    }

    /// Removes files that no attachment refers to any more
    /// (for example after a subject with materials was deleted).
    static func removeOrphanedFiles(context: ModelContext) {
        let attachments = (try? context.fetch(FetchDescriptor<Attachment>())) ?? []
        let images = (try? context.fetch(FetchDescriptor<NoteImage>())) ?? []
        let audio = (try? context.fetch(FetchDescriptor<NoteAudio>())) ?? []
        let known = Set(attachments.map(\.storedName) + images.map(\.storedName) + audio.map(\.storedName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where !known.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    static func removeAllFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    static func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
