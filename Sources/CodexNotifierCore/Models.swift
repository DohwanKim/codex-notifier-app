import Foundation

public enum CodexEventType: String, Codable, CaseIterable, Identifiable, Sendable {
    case completion
    case actionRequired = "action_required"
    case failed

    public var id: String { rawValue }
}

public enum NotificationChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case macOS = "macos"
    case telegram
    case teams

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .macOS:
            "macOS"
        case .telegram:
            "Telegram"
        case .teams:
            "Teams"
        }
    }
}

public struct CodexNotificationEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let receivedAt: Date
    public let type: CodexEventType
    public let title: String
    public let message: String

    public init(
        id: UUID = UUID(),
        receivedAt: Date = Date(),
        type: CodexEventType,
        title: String,
        message: String
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.type = type
        self.title = title
        self.message = message
    }

    public static func make(from payload: JSONValue) -> CodexNotificationEvent {
        let eventType = EventClassifier().classify(payload)
        return CodexNotificationEvent(
            type: eventType,
            title: eventType.title,
            message: MessageSummarizer().summary(from: payload, eventType: eventType)
        )
    }
}

public struct DeliveryOutcome: Codable, Equatable, Sendable {
    public let channel: NotificationChannel
    public let succeeded: Bool
    public let statusCode: Int?
    public let summary: String

    public init(
        channel: NotificationChannel,
        succeeded: Bool,
        statusCode: Int? = nil,
        summary: String
    ) {
        self.channel = channel
        self.succeeded = succeeded
        self.statusCode = statusCode
        self.summary = summary
    }
}

public struct NotificationHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let event: CodexNotificationEvent
    public let outcomes: [DeliveryOutcome]

    public init(
        id: UUID = UUID(),
        event: CodexNotificationEvent,
        outcomes: [DeliveryOutcome]
    ) {
        self.id = id
        self.event = event
        self.outcomes = outcomes
    }
}

public struct FailureLogEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let channel: NotificationChannel
    public let eventType: CodexEventType
    public let statusCode: Int?
    public let summary: String

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        channel: NotificationChannel,
        eventType: CodexEventType,
        statusCode: Int?,
        summary: String
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.channel = channel
        self.eventType = eventType
        self.statusCode = statusCode
        self.summary = summary
    }
}

extension CodexEventType {
    public var title: String {
        switch self {
        case .completion:
            "Codex 작업 완료"
        case .actionRequired:
            "Codex 입력 필요"
        case .failed:
            "Codex 작업 실패"
        }
    }
}
