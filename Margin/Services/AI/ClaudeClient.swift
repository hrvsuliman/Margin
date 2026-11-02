import Foundation
import Security

/// Stores small secrets (the user's API key, the MCP access token) in the iOS Keychain.
enum Keychain {
    private static let service = "com.hrvsuliman.margin"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Models the user can choose. Claude Opus 5.5 is the default.
enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opus: "Claude Opus 5.5 – am gründlichsten"
        case .sonnet: "Claude Sonnet 5.5 – schnell und stark"
        case .haiku: "Claude Haiku 5.5 – am günstigsten"
        }
    }

    /// Server-side refusal fallbacks exist for Opus 5.5 and Sonnet 5.5 on the Claude API.
    var supportsFallbacks: Bool { self != .haiku }
}

enum ClaudeError: LocalizedError {
    case noKey
    case offline
    case http(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noKey:
            "Kein API-Schlüssel hinterlegt. Trag ihn unter Einstellungen › Claude ein."
        case .offline:
            "Keine Internetverbindung. Der Assistent braucht Internet – alles andere in Margin funktioniert weiter offline."
        case .http(401, _):
            "Der API-Schlüssel wurde abgelehnt. Prüfe ihn unter Einstellungen › Claude."
        case .http(429, _):
            "Zu viele Anfragen gerade. Warte einen Moment und versuch es noch einmal."
        case .http(529, _), .http(503, _):
            "Claude ist gerade überlastet. Versuch es gleich noch einmal."
        case .http(let status, let message):
            "Fehler \(status): \(message)"
        case .invalidResponse:
            "Die Antwort von Claude konnte nicht gelesen werden."
        }
    }
}

/// A minimal client for the Claude Messages API (there is no official Swift SDK,
/// so this speaks plain HTTPS). Messages and content blocks are kept as JSON
/// dictionaries so that whatever Claude returns can be sent back unchanged.
struct ClaudeClient {
    static let keyAccount = "anthropic-api-key"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String
    let model: ClaudeModel

    static func stored(model: ClaudeModel) -> ClaudeClient? {
        guard let key = Keychain.read(keyAccount), !key.isEmpty else { return nil }
        return ClaudeClient(apiKey: key, model: model)
    }

    /// One request. Returns the response JSON (content, stop_reason, usage …).
    func send(system: String, messages: [[String: Any]], tools: [[String: Any]], effort: String = "medium") async throws -> [String: Any] {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
            "output_config": ["effort": effort],
            // Caches the stable prefix (system prompt, tools, earlier turns).
            "cache_control": ["type": "ephemeral"],
        ]
        if !tools.isEmpty { body["tools"] = tools }
        if model.supportsFallbacks { body["fallbacks"] = "default" }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if model.supportsFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw ClaudeError.offline
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ClaudeError.http(http.statusCode, message)
        }
        guard let json else { throw ClaudeError.invalidResponse }
        return json
    }

    // MARK: Content blocks

    static func text(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    /// A JPEG photo, downsized to at most 1568 px on the long side (Claude's sweet spot).
    static func image(jpeg data: Data) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
    }

    static func pdf(_ data: Data, title: String) -> [String: Any] {
        ["type": "document", "title": title,
         "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]]
    }
}
