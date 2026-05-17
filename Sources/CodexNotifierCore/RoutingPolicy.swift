import Foundation

public struct RoutingPolicy: Codable, Equatable, Sendable {
    private var routes: [CodexEventType: Set<NotificationChannel>]

    public static let `default` = RoutingPolicy(routes: [
        .completion: [.telegram, .teams],
        .actionRequired: [.macOS],
        .failed: [.macOS, .teams]
    ])

    public init(routes: [CodexEventType: Set<NotificationChannel>]) {
        self.routes = routes
    }

    public func channels(for eventType: CodexEventType) -> Set<NotificationChannel> {
        routes[eventType, default: []]
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

public struct CodexNotifierSettings: Codable, Equatable, Sendable {
    public var routingPolicy: RoutingPolicy
    public var telegramTimeoutSeconds: TimeInterval
    public var teamsTimeoutSeconds: TimeInterval
    public var macOSFocusOnNotificationClick: Bool

    public static let `default` = CodexNotifierSettings(
        routingPolicy: .default,
        telegramTimeoutSeconds: 5,
        teamsTimeoutSeconds: 5,
        macOSFocusOnNotificationClick: true
    )

    public init(
        routingPolicy: RoutingPolicy,
        telegramTimeoutSeconds: TimeInterval,
        teamsTimeoutSeconds: TimeInterval,
        macOSFocusOnNotificationClick: Bool
    ) {
        self.routingPolicy = routingPolicy
        self.telegramTimeoutSeconds = telegramTimeoutSeconds
        self.teamsTimeoutSeconds = teamsTimeoutSeconds
        self.macOSFocusOnNotificationClick = macOSFocusOnNotificationClick
    }

    private enum CodingKeys: String, CodingKey {
        case routingPolicy
        case telegramTimeoutSeconds
        case teamsTimeoutSeconds
        case macOSFocusOnNotificationClick
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
    }
}
