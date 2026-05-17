import Foundation

public enum CodexPayloadParser {
    public static func parse(_ string: String) throws -> JSONValue {
        try parse(Data(string.utf8))
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

public struct EventClassifier: Sendable {
    public init() {}

    public func classify(_ payload: JSONValue) -> CodexEventType {
        if ["type", "event"].contains(where: { normalizedString(payload[$0]) == "approval-requested" }) {
            return .actionRequired
        }

        if ["status", "turn_status", "result"].contains(where: { normalizedString(payload[$0]) == "failed" }) {
            return .failed
        }

        return .completion
    }

    private func normalizedString(_ value: JSONValue?) -> String? {
        value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct MessageSummarizer: Sendable {
    public let maxLength: Int

    public init(maxLength: Int = 180) {
        self.maxLength = maxLength
    }

    public func summary(from payload: JSONValue, eventType: CodexEventType) -> String {
        let rawSummary = lastAssistantMessage(in: payload)
            ?? firstString(in: payload, keys: ["message", "summary", "title", "text"])
            ?? eventType.defaultMessage

        return truncate(normalizeWhitespace(rawSummary))
    }

    public func fullMessage(from payload: JSONValue) -> String? {
        guard let message = lastAssistantMessage(in: payload)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return message
    }

    private func lastAssistantMessage(in value: JSONValue) -> String? {
        assistantMessages(in: value).last
    }

    private func assistantMessages(in value: JSONValue) -> [String] {
        switch value {
        case let .object(object):
            var messages: [String] = []

            if object["role"]?.stringValue?.lowercased() == "assistant",
               let content = object["content"].flatMap(contentText(from:)) {
                messages.append(content)
            }

            for child in object.values {
                messages.append(contentsOf: assistantMessages(in: child))
            }

            return messages
        case let .array(values):
            return values.flatMap(assistantMessages(in:))
        case .string, .number, .bool, .null:
            return []
        }
    }

    private func contentText(from value: JSONValue) -> String? {
        switch value {
        case let .string(text):
            return text
        case let .array(values):
            let parts = values.compactMap(contentText(from:))
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        case let .object(object):
            if let text = object["text"]?.stringValue {
                return text
            }
            if let content = object["content"].flatMap(contentText(from:)) {
                return content
            }
            return nil
        case .number, .bool, .null:
            return nil
        }
    }

    private func firstString(in value: JSONValue, keys: [String]) -> String? {
        guard case let .object(object) = value else { return nil }

        for key in keys {
            if let text = object[key]?.stringValue, !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func truncate(_ value: String) -> String {
        guard value.count > maxLength else { return value }
        guard maxLength > 3 else { return String(value.prefix(maxLength)) }

        let prefixLength = maxLength - 3
        let prefix = value.prefix(prefixLength).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }
}

extension CodexEventType {
    fileprivate var defaultMessage: String {
        switch self {
        case .completion:
            "Codex 작업이 완료되었습니다."
        case .actionRequired:
            "Codex가 사용자 입력을 기다립니다."
        case .failed:
            "Codex 작업이 실패했습니다."
        }
    }
}
