import Testing
import UserNotifications
import CodexNotifierCore
@testable import CodexNotifierApp

@Suite("Codex notifier app")
struct CodexNotifierAppTests {
    @Test("settings sidebar shows channel tabs without routing")
    func settingsSidebarShowsChannelTabsWithoutRouting() {
        #expect(SettingsSidebarItem.allCases == [.codex, .macOS, .telegram, .teams, .diagnostics])
        #expect(SettingsSidebarItem.allCases.first == .codex)
        #expect(SettingsSidebarItem.allCases.map(\.title) == ["Codex", "macOS", "Telegram", "Teams", "진단"])
    }

    @Test("foreground macOS notifications present banner, list, and sound")
    func foregroundNotificationPresentationOptions() {
        let options = ForegroundNotificationPresenter.presentationOptions

        #expect(options.contains(.banner))
        #expect(options.contains(.list))
        #expect(options.contains(.sound))
    }

    @Test("macOS notification focus user info stores focus target")
    func macOSNotificationFocusUserInfoStoresTarget() throws {
        let target = MacOSFocusTarget(
            bundleIdentifier: "com.jetbrains.intellij",
            processIdentifier: 44317,
            appName: "IntelliJ IDEA",
            terminalKind: "JetBrains-JediTerm",
            terminalSessionIdentifier: "jetbrains-session"
        )
        let userInfo = MacOSNotificationFocusUserInfo.make(focusTarget: target)

        #expect(MacOSNotificationFocusUserInfo.focusTarget(from: userInfo) == target)
    }

    @Test("foreground notification presenter focuses on default click and view action")
    func foregroundNotificationPresenterFocusActions() {
        #expect(ForegroundNotificationPresenter.shouldRequestFocus(actionIdentifier: UNNotificationDefaultActionIdentifier))
        #expect(ForegroundNotificationPresenter.shouldRequestFocus(actionIdentifier: ForegroundNotificationPresenter.focusActionIdentifier))
        #expect(!ForegroundNotificationPresenter.shouldRequestFocus(actionIdentifier: UNNotificationDismissActionIdentifier))
    }

    @Test("macOS focus controller activates the requested focus target")
    func macOSFocusControllerActivatesTarget() {
        var activatedTargets: [MacOSFocusTarget] = []
        let controller = MacOSFocusController { target in
            activatedTargets.append(target)
            return true
        }
        let target = MacOSFocusTarget(
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 42352,
            appName: "Code",
            terminalKind: "vscode",
            terminalSessionIdentifier: "vscode-session"
        )

        #expect(controller.focus(target) == true)
        #expect(activatedTargets == [target])
    }

    @Test("menu bar status icon state prioritizes failures over setup warnings")
    func menuBarStatusIconStatePriority() {
        #expect(MenuBarStatusIconState.make(hasFailures: false, hasMissingConfiguredChannel: false) == .normal)
        #expect(MenuBarStatusIconState.make(hasFailures: false, hasMissingConfiguredChannel: true) == .warning)
        #expect(MenuBarStatusIconState.make(hasFailures: true, hasMissingConfiguredChannel: false) == .failure)
        #expect(MenuBarStatusIconState.make(hasFailures: true, hasMissingConfiguredChannel: true) == .failure)
    }

    @MainActor
    @Test("menu bar status icon image is a template image at requested size")
    func menuBarStatusIconImageProperties() throws {
        let image = MenuBarStatusIconImage.make(for: .normal, pointSize: 24)

        #expect(image.isTemplate)
        #expect(image.size.width == 24)
        #expect(image.size.height == 24)
        #expect(try #require(image.tiffRepresentation).isEmpty == false)
    }

    @Test("macOS detail hides permission request when notifications are authorized")
    func macOSAuthorizedDetailState() {
        let state = SettingsChannelDetailState.make(
            channel: .macOS,
            routingPolicy: routingPolicy(enabling: .macOS, for: [.actionRequired]),
            macOSAuthorizationStatus: .authorized,
            telegramBotToken: "",
            telegramChatID: "",
            teamsWebhookURL: "",
            failures: []
        )

        #expect(state.status == .connected)
        #expect(state.statusText == "권한 허용")
        #expect(state.showsMacOSPermissionRequest == false)
        #expect(state.latestError == nil)
    }

    @Test("macOS detail asks for permission when notifications are denied")
    func macOSDeniedDetailState() {
        let state = SettingsChannelDetailState.make(
            channel: .macOS,
            routingPolicy: routingPolicy(enabling: .macOS, for: [.failed]),
            macOSAuthorizationStatus: .denied,
            telegramBotToken: "",
            telegramChatID: "",
            teamsWebhookURL: "",
            failures: []
        )

        #expect(state.status == .needsSetup)
        #expect(state.statusText == "권한 꺼짐")
        #expect(state.showsMacOSPermissionRequest)
        #expect(state.latestError?.summary == "macOS 알림 권한이 꺼져 있습니다.")
    }

    @Test("unused macOS detail does not ask for notification permission")
    func macOSUnusedDetailState() {
        let state = SettingsChannelDetailState.make(
            channel: .macOS,
            routingPolicy: .default,
            macOSAuthorizationStatus: .denied,
            telegramBotToken: "",
            telegramChatID: "",
            teamsWebhookURL: "",
            failures: []
        )

        #expect(state.status == .unused)
        #expect(state.statusText == "미사용")
        #expect(!state.showsMacOSPermissionRequest)
        #expect(state.latestError == nil)
    }

    @Test("Telegram detail reports missing credentials")
    func telegramMissingCredentialState() {
        let state = SettingsChannelDetailState.make(
            channel: .telegram,
            routingPolicy: routingPolicy(enabling: .telegram, for: [.completion]),
            macOSAuthorizationStatus: .authorized,
            telegramBotToken: "token",
            telegramChatID: "",
            teamsWebhookURL: "",
            failures: []
        )

        #expect(state.status == .needsSetup)
        #expect(state.statusText == "설정 필요")
        #expect(state.latestError?.summary == "Telegram Bot Token과 Chat ID를 저장해 주세요.")
    }

    @Test("unused Telegram detail does not require credentials")
    func telegramUnusedDetailState() {
        let state = SettingsChannelDetailState.make(
            channel: .telegram,
            routingPolicy: .default,
            macOSAuthorizationStatus: .authorized,
            telegramBotToken: "",
            telegramChatID: "",
            teamsWebhookURL: "",
            failures: []
        )

        #expect(state.status == .unused)
        #expect(state.statusText == "미사용")
        #expect(state.latestError == nil)
    }

    @Test("channel detail filters recent failures by channel")
    func channelDetailFiltersFailures() {
        let teamsFailure = FailureLogEntry(
            channel: .teams,
            eventType: .failed,
            statusCode: 401,
            summary: "HTTP 401"
        )
        let telegramFailure = FailureLogEntry(
            channel: .telegram,
            eventType: .failed,
            statusCode: 400,
            summary: "HTTP 400"
        )

        let state = SettingsChannelDetailState.make(
            channel: .teams,
            routingPolicy: routingPolicy(enabling: .teams, for: [.failed]),
            macOSAuthorizationStatus: .authorized,
            telegramBotToken: "token",
            telegramChatID: "chat",
            teamsWebhookURL: "https://example.com/hook",
            failures: [teamsFailure, telegramFailure]
        )

        #expect(state.status == .failed)
        #expect(state.statusText == "최근 실패")
        #expect(state.latestError?.summary == "HTTP 401")
        #expect(state.recentFailures.map(\.summary) == ["HTTP 401"])
    }

    private func routingPolicy(
        enabling channel: NotificationChannel,
        for eventTypes: Set<CodexEventType>
    ) -> RoutingPolicy {
        var policy = RoutingPolicy.default
        for eventType in eventTypes {
            policy.set(channel, enabled: true, for: eventType)
        }
        return policy
    }
}
