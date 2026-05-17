import Foundation

public struct TelegramRequestBuilder: Sendable {
    private let token: String
    private let chatID: String

    public init(token: String, chatID: String) {
        self.token = token
        self.chatID = chatID
    }

    public func makeRequest(for event: CodexNotificationEvent) throws -> HTTPRequestSpec {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw RequestBuilderError.invalidURL
        }

        return HTTPRequestSpec(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: try jsonData([
                "chat_id": chatID,
                "text": "\(event.title)\n\(event.message)"
            ])
        )
    }
}

public struct TeamsRequestBuilder: Sendable {
    private let webhookURL: URL

    public init(webhookURL: URL) {
        self.webhookURL = webhookURL
    }

    public func makeRequest(for event: CodexNotificationEvent) throws -> HTTPRequestSpec {
        HTTPRequestSpec(
            url: webhookURL,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: try jsonData([
                "text": "\(event.title)\n\(event.message)"
            ])
        )
    }
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
        throw RequestBuilderError.invalidJSONBody
    }

    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
