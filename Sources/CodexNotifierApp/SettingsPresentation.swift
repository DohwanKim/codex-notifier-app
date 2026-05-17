import CodexNotifierCore
import UserNotifications

enum SettingsSidebarItem: Hashable, CaseIterable, Identifiable {
    case codex
    case macOS
    case telegram
    case teams
    case routing
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .codex:
            "Codex"
        case .macOS:
            "macOS"
        case .telegram:
            "Telegram"
        case .teams:
            "Teams"
        case .routing:
            "라우팅"
        case .diagnostics:
            "진단"
        }
    }

    var systemImage: String {
        switch self {
        case .codex:
            "terminal"
        case .macOS:
            "bell.badge"
        case .telegram:
            "paperplane"
        case .teams:
            "person.2.wave.2"
        case .routing:
            "arrow.triangle.branch"
        case .diagnostics:
            "stethoscope"
        }
    }

}

enum SettingsChannelStatus: Equatable {
    case connected
    case needsSetup
    case failed
}

struct SettingsChannelIssue: Equatable {
    let summary: String
    let statusCode: Int?
}

struct SettingsChannelDetailState: Equatable {
    let channel: NotificationChannel
    let status: SettingsChannelStatus
    let statusText: String
    let description: String
    let showsMacOSPermissionRequest: Bool
    let latestError: SettingsChannelIssue?
    let recentFailures: [FailureLogEntry]

    static func make(
        channel: NotificationChannel,
        macOSAuthorizationStatus: UNAuthorizationStatus,
        telegramBotToken: String,
        telegramChatID: String,
        teamsWebhookURL: String,
        failures: [FailureLogEntry]
    ) -> SettingsChannelDetailState {
        let recentFailures = failures.filter { $0.channel == channel }
        let setupIssue = setupIssue(
            for: channel,
            macOSAuthorizationStatus: macOSAuthorizationStatus,
            telegramBotToken: telegramBotToken,
            telegramChatID: telegramChatID,
            teamsWebhookURL: teamsWebhookURL
        )
        let latestFailure = recentFailures.first.map {
            SettingsChannelIssue(summary: $0.summary, statusCode: $0.statusCode)
        }
        let latestError = setupIssue ?? latestFailure
        let status: SettingsChannelStatus = {
            if setupIssue != nil {
                return .needsSetup
            }
            if !recentFailures.isEmpty {
                return .failed
            }
            return .connected
        }()

        return SettingsChannelDetailState(
            channel: channel,
            status: status,
            statusText: statusText(
                for: channel,
                status: status,
                macOSAuthorizationStatus: macOSAuthorizationStatus
            ),
            description: description(for: channel),
            showsMacOSPermissionRequest: channel == .macOS && setupIssue != nil,
            latestError: latestError,
            recentFailures: Array(recentFailures.prefix(5))
        )
    }

    private static func setupIssue(
        for channel: NotificationChannel,
        macOSAuthorizationStatus: UNAuthorizationStatus,
        telegramBotToken: String,
        telegramChatID: String,
        teamsWebhookURL: String
    ) -> SettingsChannelIssue? {
        switch channel {
        case .macOS:
            switch macOSAuthorizationStatus {
            case .authorized, .provisional:
                return nil
            case .denied:
                return SettingsChannelIssue(summary: "macOS 알림 권한이 꺼져 있습니다.", statusCode: nil)
            case .notDetermined:
                return SettingsChannelIssue(summary: "macOS 알림 권한을 허용해 주세요.", statusCode: nil)
            @unknown default:
                return SettingsChannelIssue(summary: "macOS 알림 권한 상태를 확인해 주세요.", statusCode: nil)
            }
        case .telegram:
            guard !telegramBotToken.isEmpty, !telegramChatID.isEmpty else {
                return SettingsChannelIssue(summary: "Telegram Bot Token과 Chat ID를 저장해 주세요.", statusCode: nil)
            }
            return nil
        case .teams:
            guard !teamsWebhookURL.isEmpty else {
                return SettingsChannelIssue(summary: "Teams Workflow Webhook URL을 저장해 주세요.", statusCode: nil)
            }
            return nil
        }
    }

    private static func statusText(
        for channel: NotificationChannel,
        status: SettingsChannelStatus,
        macOSAuthorizationStatus: UNAuthorizationStatus
    ) -> String {
        switch status {
        case .connected:
            if channel == .macOS {
                return "권한 허용"
            }
            return "연결됨"
        case .needsSetup:
            if channel == .macOS {
                switch macOSAuthorizationStatus {
                case .denied:
                    return "권한 꺼짐"
                case .notDetermined:
                    return "권한 필요"
                case .authorized, .provisional:
                    return "권한 허용"
                @unknown default:
                    return "확인 필요"
                }
            }
            return "설정 필요"
        case .failed:
            return "최근 실패"
        }
    }

    private static func description(for channel: NotificationChannel) -> String {
        switch channel {
        case .macOS:
            "Codex 입력 필요와 실패 알림을 macOS 시스템 알림으로 받습니다."
        case .telegram:
            "Telegram 봇으로 작업 완료와 실패 알림을 전송합니다."
        case .teams:
            "Teams Workflow Webhook으로 팀 채널에 알림을 전송합니다."
        }
    }
}
