import SwiftData
import XCTest
@testable import Margin

@MainActor
final class MarginToolsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        ReminderService.isEnabled = false
        container = try Persistence.inMemoryContainer()
        context.insert(SchoolSubject(name: "Biologie", colorKey: "green"))
        try context.save()
    }

    private func object(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    func testEveryToolHasAValidSchema() {
        for spec in MarginTools.specs {
            XCTAssertTrue(JSONSerialization.isValidJSONObject(spec.apiDefinition), spec.name)
            XCTAssertEqual(spec.schema["type"] as? String, "object", spec.name)
        }
        XCTAssertEqual(Set(MarginTools.specs.map(\.name)).count, MarginTools.specs.count, "tool names must be unique")
    }

    func testAddTaskThenListIt() throws {
        let created = MarginTools.call("add_task", input: ["title": "Zellaufbau lernen", "subject": "bio", "due_date": "2026-11-20"],
                                       context: context)
        XCTAssertFalse(created.isError, created.text)
        let listed = try XCTUnwrap(try object(MarginTools.call("list_tasks", input: [:], context: context).text) as? [[String: Any]])
        XCTAssertEqual(listed.first?["title"] as? String, "Zellaufbau lernen")
        XCTAssertEqual(listed.first?["subject"] as? String, "Biologie")
        XCTAssertTrue((listed.first?["due"] as? String ?? "").hasPrefix("2026-11-20"))
    }

    func testUnknownSubjectIsAHelpfulError() {
        let outcome = MarginTools.call("add_exam", input: ["subject": "Astrologie", "date": "2026-12-01"], context: context)
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.text.contains("Biologie"), "the error should list the existing subjects")
    }

    func testExamWithTopicsAndUnderstanding() throws {
        let exam = MarginTools.call("add_exam", input: ["subject": "Biologie", "date": "2026-12-01", "topics": ["Zelle", "Mitose"]],
                                    context: context)
        XCTAssertFalse(exam.isError, exam.text)
        let set = MarginTools.call("set_understanding", input: ["subject": "Biologie", "topic": "mitose", "level": 3], context: context)
        XCTAssertFalse(set.isError, set.text)
        let exams = try XCTUnwrap(try object(MarginTools.call("list_exams", input: [:], context: context).text) as? [[String: Any]])
        let topics = try XCTUnwrap(exams.first?["topics"] as? [[String: Any]])
        XCTAssertEqual(topics.map { $0["title"] as? String }, ["Zelle", "Mitose"])
        XCTAssertEqual(topics.last?["understanding"] as? Int, 3)
    }

    func testCreatedNoteBecomesFlashcards() throws {
        let outcome = MarginTools.call("create_note", input: [
            "title": "Zelle", "subject": "Biologie",
            "body": "# Zelle\n- Zellkern :: enthält die DNA\n- Mitochondrien :: Kraftwerke der Zelle",
        ], context: context)
        XCTAssertFalse(outcome.isError, outcome.text)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Flashcard>()), 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NoteDocument>()).first?.title, "Zelle")
    }

    func testDatesAcceptGermanFormat() {
        let date = MarginTools.parseDate("20.11.2026")
        XCTAssertEqual(date, Calendar.school.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        XCTAssertNil(MarginTools.parseDate("bald"))
    }

    // MARK: MCP

    func testMCPInitializeListAndCall() throws {
        let initialize = try XCTUnwrap(MCPHandler.handle(
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]],
            allowWrites: false, context: context
        ))
        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil(result["capabilities"] as? [String: Any])

        XCTAssertNil(MCPHandler.handle(["jsonrpc": "2.0", "method": "notifications/initialized"], allowWrites: false, context: context))

        let list = try XCTUnwrap(MCPHandler.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"], allowWrites: false, context: context))
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "get_overview" })
        XCTAssertFalse(tools.contains { $0["name"] as? String == "add_task" }, "write tools are hidden when writing is off")

        let blocked = try XCTUnwrap(MCPHandler.handle(
            ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "add_task", "arguments": ["title": "X"]]],
            allowWrites: false, context: context
        ))
        XCTAssertEqual((blocked["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SchoolTask>()), 0)

        let allowed = try XCTUnwrap(MCPHandler.handle(
            ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "add_task", "arguments": ["title": "X"]]],
            allowWrites: true, context: context
        ))
        XCTAssertEqual((allowed["result"] as? [String: Any])?["isError"] as? Bool, false)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SchoolTask>()), 1)

        let unknown = try XCTUnwrap(MCPHandler.handle(["jsonrpc": "2.0", "id": 5, "method": "resources/list"], allowWrites: true, context: context))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testHTTPRequestNeedsTheWholeBody() throws {
        let head = "POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer abc\r\nContent-Length: 13\r\n\r\n"
        XCTAssertNil(HTTPRequest(Data((head + "{\"id\":").utf8)))
        let request = try XCTUnwrap(HTTPRequest(Data((head + "{\"id\":1,\"a\":2}").utf8)))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertEqual(request.body.count, 13)
    }
}
