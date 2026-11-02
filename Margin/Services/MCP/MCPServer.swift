import Foundation
import Network
import Observation
import Security
import SwiftData
import UIKit

/// The Model Context Protocol messages Margin understands (JSON-RPC 2.0).
/// Kept separate from the network code so it can be unit-tested.
@MainActor
enum MCPHandler {
    static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]

    static let instructions = """
    Margin ist die Schul-App der Nutzerin oder des Nutzers (Deutschland, Daten auf Deutsch). \
    Mit diesen Werkzeugen kannst du Stundenplan, Aufgaben, Prüfungen mit Themen und Lernstand, Notizen, \
    Karteikarten und Lernstatistik lesen und – falls in der App erlaubt – Aufgaben, Prüfungen, Themen, \
    Karteikarten und Notizen anlegen. Beginne mit get_overview. Notizen erscheinen in der Handschrift \
    der Nutzerin oder des Nutzers; Markup: "# ", "## ", "- ", "Begriff :: Erklärung".
    """

    /// Handles one JSON-RPC message. Returns nil for notifications (no reply).
    static func handle(_ message: [String: Any], allowWrites: Bool, context: ModelContext) -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else { return nil } // notifications/initialized and other notifications

        func result(_ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }
        func error(_ code: Int, _ text: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let version = supportedVersions.contains(requested) ? requested : supportedVersions[1]
            return result([
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "margin", "title": "Margin", "version": BuildInfo.current.version],
                "instructions": instructions,
            ])
        case "ping":
            return result([:])
        case "tools/list":
            let tools = MarginTools.specs.filter { allowWrites || $0.readOnly }.map(\.mcpDefinition)
            return result(["tools": tools])
        case "tools/call":
            guard let name = params["name"] as? String, let spec = MarginTools.spec(named: name) else {
                return error(-32602, "Unbekanntes Werkzeug")
            }
            guard allowWrites || spec.readOnly else {
                return result(["isError": true, "content": [[
                    "type": "text",
                    "text": "Änderungen sind in Margin gerade nicht erlaubt (Einstellungen › Claude verbinden › Änderungen erlauben).",
                ]]])
            }
            let outcome = MarginTools.call(name, input: params["arguments"] as? [String: Any] ?? [:], context: context)
            return result(["isError": outcome.isError, "content": [["type": "text", "text": outcome.text]]])
        default:
            return error(-32601, "Method not found: \(method)")
        }
    }
}

/// A tiny HTTP server on the local network that speaks MCP ("Streamable HTTP",
/// plain JSON responses). It only runs while Margin is open – iOS doesn't
/// allow apps to serve in the background.
@MainActor
@Observable
final class MCPServer {
    static let shared = MCPServer()
    static let port: UInt16 = 8765
    private static let tokenAccount = "mcp-token"

    private(set) var isRunning = false
    private(set) var requestCount = 0
    private(set) var lastActivity: String?
    private(set) var errorMessage: String?
    var allowWrites: Bool = UserDefaults.standard.bool(forKey: "mcp.allowWrites") {
        didSet { UserDefaults.standard.set(allowWrites, forKey: "mcp.allowWrites") }
    }

    private var listener: NWListener?
    private var context: ModelContext?

    /// Secret the PC must send as `Authorization: Bearer …`.
    var token: String {
        if let existing = Keychain.read(Self.tokenAccount) { return existing }
        return regenerateToken()
    }

    @discardableResult
    func regenerateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        Keychain.write(value, account: Self.tokenAccount)
        return value
    }

    var address: String? {
        Self.wifiAddress().map { "http://\($0):\(Self.port)/mcp" }
    }

    func start(context: ModelContext) {
        guard !isRunning else { return }
        self.context = context
        errorMessage = nil
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    if case .failed(let error) = state {
                        self?.errorMessage = "Server gestoppt: \(error.localizedDescription)"
                        self?.stop()
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            isRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = "Server konnte nicht starten: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(buffer) {
                    self.respond(to: request, on: connection)
                } else if isComplete || error != nil || buffer.count > 8 << 20 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        guard request.path.hasPrefix("/mcp") else {
            return send(status: 404, body: Data("Not found".utf8), on: connection)
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return send(status: 401, body: Data(#"{"error":"unauthorized"}"#.utf8), on: connection)
        }
        guard request.method == "POST" else {
            // No server-initiated streams: GET is not offered (allowed by the spec).
            return send(status: 405, body: Data(), on: connection)
        }
        guard let context,
              let message = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            let reply: [String: Any] = ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]]
            return send(status: 400, body: (try? JSONSerialization.data(withJSONObject: reply)) ?? Data(), on: connection)
        }

        requestCount += 1
        if let method = message["method"] as? String {
            let tool = (message["params"] as? [String: Any])?["name"] as? String
            lastActivity = "\(Fmt.time(.now)) · \(tool.flatMap { MarginTools.spec(named: $0)?.label } ?? method)"
        }
        guard let reply = MCPHandler.handle(message, allowWrites: allowWrites, context: context) else {
            return send(status: 202, body: Data(), on: connection)
        }
        let body = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        send(status: 200, body: body, contentType: "application/json", on: connection)
    }

    private func send(status: Int, body: Data, contentType: String = "application/json", on connection: NWConnection) {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: \(contentType)\r\n" }
        if status == 405 { head += "Allow: POST\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// The phone's Wi-Fi IPv4 address.
    static func wifiAddress() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            let interface = entry.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
               String(cString: interface.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            current = interface.ifa_next
        }
        return nil
    }
}

/// A complete HTTP/1.1 request, or nil while bytes are still missing.
struct HTTPRequest {
    let method: String
    let path: String
    /// Lower-cased header names.
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = separator.upperBound
        guard data.count - bodyStart >= length else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1])
        self.headers = headers
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }
}
