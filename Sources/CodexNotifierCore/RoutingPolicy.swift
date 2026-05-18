import Foundation

public struct RoutingPolicy: Codable, Equatable, Sendable {
    private var routes: [CodexEventType: Set<NotificationChannel>]

    public static let `default` = RoutingPolicy(routes: [:])

    public init(routes: [CodexEventType: Set<NotificationChannel>]) {
        self.routes = routes
    }

    public func channels(for eventType: CodexEventType) -> Set<NotificationChannel> {
        routes[eventType, default: []]
    }

    public func isChannelEnabled(_ channel: NotificationChannel) -> Bool {
        CodexEventType.allCases.contains {
            channels(for: $0).contains(channel)
        }
    }

    public static func recommendedEvents(for channel: NotificationChannel) -> Set<CodexEventType> {
        switch channel {
        case .macOS:
            [.actionRequired, .failed]
        case .telegram:
            [.completion]
        case .teams:
            [.completion, .failed]
        }
    }

    public mutating func setChannel(_ channel: NotificationChannel, enabled: Bool) {
        let recommendedEvents = RoutingPolicy.recommendedEvents(for: channel)

        for eventType in CodexEventType.allCases {
            set(channel, enabled: enabled && recommendedEvents.contains(eventType), for: eventType)
        }
    }

    public mutating func set(
        _ channel: NotificationChannel,
        enabled: Bool,
        for eventType: CodexEventType
    ) {
        var channels = routes[eventType, default: []]

        if enabled {
            channels.insert(channel)
        } else {
            channels.remove(channel)
        }

        routes[eventType] = channels
    }
}

public struct NotificationMessageOptions: Codable, Equatable, Sendable {
    public var includeFullMessage: Bool
    public var includeFolderName: Bool
    public var includeBranchName: Bool

    public static let `default` = NotificationMessageOptions(
        includeFullMessage: false,
        includeFolderName: false,
        includeBranchName: false
    )

    public init(
        includeFullMessage: Bool,
        includeFolderName: Bool,
        includeBranchName: Bool
    ) {
        self.includeFullMessage = includeFullMessage
        self.includeFolderName = includeFolderName
        self.includeBranchName = includeBranchName
    }
}

public struct NotificationMessagePolicy: Codable, Equatable, Sendable {
    private var optionsByChannel: [NotificationChannel: NotificationMessageOptions]

    public static let `default` = NotificationMessagePolicy(optionsByChannel: [:])

    public init(optionsByChannel: [NotificationChannel: NotificationMessageOptions]) {
        self.optionsByChannel = optionsByChannel
    }

    public func options(for channel: NotificationChannel) -> NotificationMessageOptions {
        optionsByChannel[channel, default: .default]
    }

    public mutating func set(
        _ option: WritableKeyPath<NotificationMessageOptions, Bool>,
        enabled: Bool,
        for channel: NotificationChannel
    ) {
        var options = options(for: channel)
        options[keyPath: option] = enabled
        optionsByChannel[channel] = options
    }
}

public struct CodexNotifierSettings: Codable, Equatable, Sendable {
    public var routingPolicy: RoutingPolicy
    public var telegramTimeoutSeconds: TimeInterval
    public var teamsTimeoutSeconds: TimeInterval
    public var macOSFocusOnNotificationClick: Bool
    public var messagePolicy: NotificationMessagePolicy

    public static let `default` = CodexNotifierSettings(
        routingPolicy: .default,
        telegramTimeoutSeconds: 5,
        teamsTimeoutSeconds: 5,
        macOSFocusOnNotificationClick: true,
        messagePolicy: .default
    )

    public init(
        routingPolicy: RoutingPolicy,
        telegramTimeoutSeconds: TimeInterval,
        teamsTimeoutSeconds: TimeInterval,
        macOSFocusOnNotificationClick: Bool,
        messagePolicy: NotificationMessagePolicy = .default
    ) {
        self.routingPolicy = routingPolicy
        self.telegramTimeoutSeconds = telegramTimeoutSeconds
        self.teamsTimeoutSeconds = teamsTimeoutSeconds
        self.macOSFocusOnNotificationClick = macOSFocusOnNotificationClick
        self.messagePolicy = messagePolicy
    }

    private enum CodingKeys: String, CodingKey {
        case routingPolicy
        case telegramTimeoutSeconds
        case teamsTimeoutSeconds
        case macOSFocusOnNotificationClick
        case messagePolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CodexNotifierSettings.default

        routingPolicy = try container.decodeIfPresent(RoutingPolicy.self, forKey: .routingPolicy) ?? defaults.routingPolicy
        telegramTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .telegramTimeoutSeconds)
            ?? defaults.telegramTimeoutSeconds
        teamsTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .teamsTimeoutSeconds)
            ?? defaults.teamsTimeoutSeconds

        // 설정 파일/ UserDefaults는 이전 버전 데이터가 남아 있을 수 있다. 이 값이 없으면 기존 라우팅과
        // timeout은 유지하면서, 새 클릭 포커스 기능만 기본값으로 켠다.
        macOSFocusOnNotificationClick = try container.decodeIfPresent(
            Bool.self,
            forKey: .macOSFocusOnNotificationClick
        ) ?? defaults.macOSFocusOnNotificationClick

        // 메시지 구성은 채널별 노출 정책이므로, 이전 버전 설정에 값이 없으면 모든 추가 정보를 숨긴다.
        // 기본 off를 유지해야 기존 사용자가 원치 않는 전문/폴더/브랜치 정보를 외부 채널로 보내지 않는다.
        messagePolicy = try container.decodeIfPresent(
            NotificationMessagePolicy.self,
            forKey: .messagePolicy
        ) ?? defaults.messagePolicy
    }
}
