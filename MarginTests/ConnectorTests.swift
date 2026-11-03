import SwiftData
import XCTest
@testable import Margin

@MainActor
final class ConnectorTests: XCTestCase {
    func testSnapshotIsValidJSONWithToolsAndData() throws {
        ReminderService.isEnabled = false
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        let math = SchoolSubject(name: "Mathematik", colorKey: "blue")
        context.insert(math)
        let note = NoteDocument(title: "Funktionen")
        note.body = "# Funktionen\nf(x) :: eine Zuordnung"
        note.subjectUID = math.uid
        context.insert(note)
        let task = SchoolTask(title: "S. 42", dueDate: .now)
        context.insert(task)
        task.subject = math
        try context.save()

        let snapshot = ConnectorSync.snapshot(context: context, allowWrites: true)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(snapshot))
        let tools = try XCTUnwrap(snapshot["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, MarginTools.specs.count)
        let data = try XCTUnwrap(snapshot["data"] as? [String: Any])
        let tasks = try XCTUnwrap(data["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.first?["subject"] as? String, "Mathematik")
        let notes = try XCTUnwrap(snapshot["notes"] as? [[String: Any]])
        XCTAssertEqual(notes.first?["body"] as? String, note.body)
        let index = try XCTUnwrap(data["notes"] as? [[String: Any]])
        XCTAssertNil(index.first?["body"], "the note index must stay small")
        XCTAssertNotNil((data["topics"] as? [String: Any])?["Mathematik"])
    }

    func testChatHistoryIsBackedUp() throws {
        ReminderService.isEnabled = false
        let container = try Persistence.inMemoryContainer()
        let context = container.mainContext
        let thread = ChatThread(engine: .onDevice)
        thread.title = "Mitose erklären"
        thread.itemsData = Data("[]".utf8)
        context.insert(thread)
        try context.save()

        let data = try BackupService.export(context: context, settings: nil)
        try BackupService.restore(BackupService.decode(data), context: context, settings: nil)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<ChatThread>()).first)
        XCTAssertEqual(restored.title, "Mitose erklären")
        XCTAssertEqual(restored.engine, .onDevice)
    }
}
