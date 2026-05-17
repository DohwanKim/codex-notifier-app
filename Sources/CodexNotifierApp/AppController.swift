import AppKit
import CodexNotifierCore
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppController: ObservableObject {
    @Published var settings: CodexNotifierSettings
    @Published var history: [NotificationHistoryEntry]
    @Published var failures: [FailureLogEntry]
    @Published var telegramBotToken: String = ""
    @Published var telegramChatID: String = ""
    @Published var teamsWebhookURL: String = ""
    @Published var macOSAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var lastError: String?
    @Published var codexIntegrationStatus: CodexCLIIntegrationStatus
    @Published var codexIntegrationIssue: String?
    @Published var codexIntegrationMessage: String?

    private let settingsStore: SettingsStore
    private let historyStore: NotificationHistoryStore
    private let keychain: KeychainSecretStore
    private let inboxStore: InboxStore
    private let codexConfigInstaller: CodexCLIConfigInstaller
    private let focusController: MacOSFocusController
    private let foregroundNotificationPresenter = ForegroundNotificationPresenter()
    private var notificationObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?

    init(
        settingsStore: SettingsStore = SettingsStore(),
        historyStore: NotificationHistoryStore = NotificationHistoryStore(),
        keychain: KeychainSecretStore = KeychainSecretStore(),
        inboxStore: InboxStore = InboxStore(),
        codexConfigInstaller: CodexCLIConfigInstaller = CodexCLIConfigInstaller(),
        focusController: MacOSFocusController = MacOSFocusController()
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.keychain = keychain
        self.inboxStore = inboxStore
        self.codexConfigInstaller = codexConfigInstaller
        self.focusController = focusController
        settings = settingsStore.load()
        codexIntegrationStatus = codexConfigInstaller.status()
        historyStore.clearFailuresResolvedByHistory()
        history = historyStore.loadHistory()
        failures = historyStore.loadFailures()
        foregroundNotificationPresenter.onFocusRequested = { [weak self] target in
            Task { @MainActor in
                self?.focusNotificationTarget(target)
            }
        }
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = foregroundNotificationPresenter
        notificationCenter.setNotificationCategories([ForegroundNotificationPresenter.notificationCategory])
        loadCredentials()
        observeInboxNotifications()

        Task {
            await refreshMacOSAuthorizationStatus()
            await processPendingInbox()
        }
    }

    var recentEventSummary: String {
        guard let latest = history.first else {
            return "최근 이벤트 없음"
        }

        return "최근 이벤트: \(latest.event.title)"
    }

    var channelStatusSummary: String {
        "macOS \(macOSStatusText) / Telegram \(credentialStatusText([telegramBotToken, telegramChatID])) / Teams \(credentialStatusText([teamsWebhookURL]))"
    }

    var statusIconState: MenuBarStatusIconState {
        MenuBarStatusIconState.make(
            hasFailures: !failures.isEmpty,
            hasMissingConfiguredChannel: hasMissingConfiguredChannel
        )
    }

    var helperStatus: String {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/codex-notifier-helper")

        if FileManager.default.fileExists(atPath: helperURL.path) {
            return helperURL.path
        }

        return "앱 번들 안에서 실행하면 helper 경로가 표시됩니다."
    }

    func updateRoute(eventType: CodexEventType, channel: NotificationChannel, enabled: Bool) {
        settings.routingPolicy.set(channel, enabled: enabled, for: eventType)
        settingsStore.save(settings)
        objectWillChange.send()
    }

    func saveCredentials() {
        do {
            try keychain.save(telegramBotToken, for: .telegramBotToken)
            try keychain.save(telegramChatID, for: .telegramChatID)
            try keychain.save(teamsWebhookURL, for: .teamsWebhookURL)
            lastError = nil
        } catch {
            lastError = "Keychain 저장 실패: \(error)"
        }
    }

    func saveSettings() {
        settingsStore.save(settings)
    }

    func requestMacOSPermission() {
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await refreshMacOSAuthorizationStatus()
            } catch {
                lastError = "macOS 알림 권한 요청 실패: \(error)"
            }
        }
    }

    func sendTest(to channel: NotificationChannel) async {
        let event = CodexNotificationEvent(
            type: .completion,
            title: "Codex Notifier 테스트",
            message: "\(channel.displayName) 채널 연결 확인 메시지입니다."
        )
        let outcome = await deliver(event, focusTarget: nil, to: channel)
        record(event: event, outcomes: [outcome])
    }

    func processPendingInbox() async {
        do {
            for fileURL in try inboxStore.pendingPayloadFiles() {
                do {
                    let payloadData = try inboxStore.readPayload(at: fileURL)
                    let envelope = try CodexNotificationEnvelope.decode(from: payloadData)
                    let event = CodexNotificationEvent.make(from: envelope.payload)
                    let outcomes = await deliver(event, focusTarget: envelope.focusTarget)
                    record(event: event, outcomes: outcomes)
                    try inboxStore.removePayload(at: fileURL)
                } catch {
                    try? inboxStore.moveToFailed(fileURL)
                    appendFailure(
                        FailureLogEntry(
                            channel: .macOS,
                            eventType: .failed,
                            statusCode: nil,
                            summary: "Inbox 처리 실패: \(error)"
                        )
                    )
                }
            }
        } catch {
            lastError = "Inbox 스캔 실패: \(error)"
        }
    }

    func openLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([inboxStore.rootDirectory])
    }

    func configureCodexCLI() {
        do {
            let result = try codexConfigInstaller.install()
            refreshCodexIntegrationStatus()
            codexIntegrationIssue = nil
            codexIntegrationMessage = result.changed
                ? "config.toml을 백업하고 Codex notify를 연결했습니다."
                : "Codex notify가 이미 연결되어 있습니다."
        } catch {
            refreshCodexIntegrationStatus()
            codexIntegrationIssue = "Codex 자동 설정 실패: \(error)"
            codexIntegrationMessage = nil
        }
    }

    func restoreCodexCLIConfig() {
        do {
            let backupURL = try codexConfigInstaller.restoreLatestBackup()
            refreshCodexIntegrationStatus()
            codexIntegrationIssue = nil
            codexIntegrationMessage = "백업에서 config.toml을 복구했습니다: \(backupURL.path)"
        } catch {
            refreshCodexIntegrationStatus()
            codexIntegrationIssue = "Codex 설정 복구 실패: \(error)"
            codexIntegrationMessage = nil
        }
    }

    func copyCodexHelperPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codexIntegrationStatus.helperPath, forType: .string)
        codexIntegrationMessage = "Helper 경로를 클립보드에 복사했습니다."
        codexIntegrationIssue = nil
    }

    func openCodexConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: codexIntegrationStatus.configPath)
        ])
    }

    func refreshCodexIntegrationStatus() {
        codexIntegrationStatus = codexConfigInstaller.status()
    }

    func openSettingsWindow() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView(controller: self)
                    .frame(width: 780, height: 620)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Codex Notifier 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func focusNotificationTarget(_ target: MacOSFocusTarget?) {
        guard settings.macOSFocusOnNotificationClick, let target else {
            return
        }

        guard focusController.focus(target) else {
            lastError = "포커스 대상 앱을 찾지 못했습니다: \(target.appName ?? target.bundleIdentifier)"
            return
        }
    }

    func refreshMacOSAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        macOSAuthorizationStatus = settings.authorizationStatus
    }

    private func observeInboxNotifications() {
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(CodexNotifierConstants.payloadCreatedNotification),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.processPendingInbox()
            }
        }
    }

    private func loadCredentials() {
        telegramBotToken = (try? keychain.read(.telegramBotToken)) ?? ""
        telegramChatID = (try? keychain.read(.telegramChatID)) ?? ""
        teamsWebhookURL = (try? keychain.read(.teamsWebhookURL)) ?? ""
    }

    private func deliver(_ event: CodexNotificationEvent, focusTarget: MacOSFocusTarget?) async -> [DeliveryOutcome] {
        let channels = settings.routingPolicy.channels(for: event.type)

        var outcomes: [DeliveryOutcome] = []
        for channel in NotificationChannel.allCases where channels.contains(channel) {
            outcomes.append(await deliver(event, focusTarget: focusTarget, to: channel))
        }
        return outcomes
    }

    private func deliver(
        _ event: CodexNotificationEvent,
        focusTarget: MacOSFocusTarget?,
        to channel: NotificationChannel
    ) async -> DeliveryOutcome {
        switch channel {
        case .macOS:
            return await sendMacOSNotification(event, focusTarget: focusTarget)
        case .telegram:
            return await sendTelegramNotification(event)
        case .teams:
            return await sendTeamsNotification(event)
        }
    }

    private func sendMacOSNotification(
        _ event: CodexNotificationEvent,
        focusTarget: MacOSFocusTarget?
    ) async -> DeliveryOutcome {
        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        macOSAuthorizationStatus = notificationSettings.authorizationStatus

        guard [.authorized, .provisional].contains(notificationSettings.authorizationStatus) else {
            return DeliveryOutcome(
                channel: .macOS,
                succeeded: false,
                summary: "macOS 알림 권한이 꺼져 있습니다."
            )
        }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.message
        content.sound = UNNotificationSound(named: UNNotificationSoundName(CodexNotifierConstants.notificationSoundName))
        content.userInfo = MacOSNotificationFocusUserInfo.make(focusTarget: focusTarget)

        if focusTarget != nil {
            content.categoryIdentifier = ForegroundNotificationPresenter.focusCategoryIdentifier
        }

        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return DeliveryOutcome(channel: .macOS, succeeded: true, summary: "전송 완료")
        } catch {
            return DeliveryOutcome(channel: .macOS, succeeded: false, summary: "macOS 전송 실패: \(error)")
        }
    }

    private func sendTelegramNotification(_ event: CodexNotificationEvent) async -> DeliveryOutcome {
        guard !telegramBotToken.isEmpty, !telegramChatID.isEmpty else {
            return DeliveryOutcome(channel: .telegram, succeeded: false, summary: "Telegram 인증 정보가 없습니다.")
        }

        do {
            let request = try TelegramRequestBuilder(
                token: telegramBotToken,
                chatID: telegramChatID
            ).makeRequest(for: event)
            return await sendHTTPRequest(
                request,
                channel: .telegram,
                timeout: settings.telegramTimeoutSeconds
            )
        } catch {
            return DeliveryOutcome(channel: .telegram, succeeded: false, summary: "Telegram 요청 생성 실패: \(error)")
        }
    }

    private func sendTeamsNotification(_ event: CodexNotificationEvent) async -> DeliveryOutcome {
        guard let webhookURL = URL(string: teamsWebhookURL), !teamsWebhookURL.isEmpty else {
            return DeliveryOutcome(channel: .teams, succeeded: false, summary: "Teams webhook URL이 없습니다.")
        }

        do {
            let request = try TeamsRequestBuilder(webhookURL: webhookURL).makeRequest(for: event)
            return await sendHTTPRequest(
                request,
                channel: .teams,
                timeout: settings.teamsTimeoutSeconds
            )
        } catch {
            return DeliveryOutcome(channel: .teams, succeeded: false, summary: "Teams 요청 생성 실패: \(error)")
        }
    }

    private func sendHTTPRequest(
        _ spec: HTTPRequestSpec,
        channel: NotificationChannel,
        timeout: TimeInterval
    ) async -> DeliveryOutcome {
        var request = URLRequest(url: spec.url, timeoutInterval: timeout)
        request.httpMethod = spec.method
        request.httpBody = spec.body

        for (field, value) in spec.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode

            guard let statusCode, (200..<300).contains(statusCode) else {
                return DeliveryOutcome(
                    channel: channel,
                    succeeded: false,
                    statusCode: statusCode,
                    summary: "HTTP \(statusCode.map(String.init) ?? "응답 코드 없음")"
                )
            }

            return DeliveryOutcome(
                channel: channel,
                succeeded: true,
                statusCode: statusCode,
                summary: "HTTP \(statusCode)"
            )
        } catch {
            return DeliveryOutcome(
                channel: channel,
                succeeded: false,
                statusCode: nil,
                summary: "네트워크 오류: \(error)"
            )
        }
    }

    private func record(event: CodexNotificationEvent, outcomes: [DeliveryOutcome]) {
        let historyEntry = NotificationHistoryEntry(event: event, outcomes: outcomes)
        historyStore.appendHistory(historyEntry)
        history = historyStore.loadHistory()

        for outcome in outcomes where outcome.succeeded {
            historyStore.clearFailures(for: outcome.channel)
        }

        for outcome in outcomes where !outcome.succeeded {
            appendFailure(
                FailureLogEntry(
                    channel: outcome.channel,
                    eventType: event.type,
                    statusCode: outcome.statusCode,
                    summary: redactor.redact(outcome.summary)
                )
            )
        }

        failures = historyStore.loadFailures()
    }

    private func appendFailure(_ entry: FailureLogEntry) {
        historyStore.appendFailure(entry)
        failures = historyStore.loadFailures()
    }

    private var macOSStatusText: String {
        switch macOSAuthorizationStatus {
        case .authorized, .provisional:
            "연결됨"
        case .denied:
            "권한 꺼짐"
        case .notDetermined:
            "권한 필요"
        @unknown default:
            "확인 필요"
        }
    }

    private func credentialStatusText(_ values: [String]) -> String {
        values.allSatisfy { !$0.isEmpty } ? "연결됨" : "미연결"
    }

    private var hasMissingConfiguredChannel: Bool {
        let routedChannels = Set(CodexEventType.allCases.flatMap { settings.routingPolicy.channels(for: $0) })

        return routedChannels.contains(.macOS) && ![.authorized, .provisional].contains(macOSAuthorizationStatus)
            || routedChannels.contains(.telegram) && (telegramBotToken.isEmpty || telegramChatID.isEmpty)
            || routedChannels.contains(.teams) && teamsWebhookURL.isEmpty
    }

    private var redactor: SecretRedactor {
        SecretRedactor(secrets: [telegramBotToken, telegramChatID, teamsWebhookURL])
    }
}
