import Foundation
import Testing
@testable import CodexNotifierCore

@Suite("Codex notifier core")
struct CodexNotifierCoreTests {
    @Test("classifies approval requests as action_required")
    func classifiesApprovalRequests() throws {
        let payload = try CodexPayloadParser.parse(#"{"type":"approval-requested"}"#)

        #expect(EventClassifier().classify(payload) == .actionRequired)
    }

    @Test("classifies failed status fields as failed")
    func classifiesFailureFromStatusFields() throws {
        let statusPayload = try CodexPayloadParser.parse(#"{"status":"failed"}"#)
        let turnStatusPayload = try CodexPayloadParser.parse(#"{"turn_status":"failed"}"#)
        let resultPayload = try CodexPayloadParser.parse(#"{"result":"failed"}"#)

        let classifier = EventClassifier()

        #expect(classifier.classify(statusPayload) == .failed)
        #expect(classifier.classify(turnStatusPayload) == .failed)
        #expect(classifier.classify(resultPayload) == .failed)
    }

    @Test("uses completion as the default event type")
    func classifiesCompletionByDefault() throws {
        let payload = try CodexPayloadParser.parse(#"{"status":"ok"}"#)

        #expect(EventClassifier().classify(payload) == .completion)
    }

    @Test("default routing matches the MVP policy")
    func defaultRoutingPolicy() {
        let policy = RoutingPolicy.default

        #expect(policy.channels(for: .completion) == [.telegram, .teams])
        #expect(policy.channels(for: .actionRequired) == [.macOS])
        #expect(policy.channels(for: .failed) == [.macOS, .teams])
    }

    @Test("message summaries prefer the last assistant message and stay short")
    func summarizesLastAssistantMessage() throws {
        let longText = String(repeating: "failure detail ", count: 30)
        let payload = try CodexPayloadParser.parse(
            """
            {
              "messages": [
                {"role": "assistant", "content": "first assistant message"},
                {"role": "user", "content": "please continue"},
                {"role": "assistant", "content": "\(longText)"}
              ]
            }
            """
        )

        let summary = MessageSummarizer(maxLength: 80).summary(from: payload, eventType: .failed)

        #expect(summary.hasPrefix("failure detail"))
        #expect(!summary.contains("first assistant message"))
        #expect(summary.count <= 80)
        #expect(summary.hasSuffix("..."))

        let event = CodexNotificationEvent.make(from: payload)
        #expect(event.fullMessage == longText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("redacts configured secrets from log text")
    func redactsSecrets() {
        let redactor = SecretRedactor(secrets: [
            "123456:telegram-token",
            "https://example.com/teams/webhook"
        ])

        let output = redactor.redact(
            "telegram=123456:telegram-token teams=https://example.com/teams/webhook ok"
        )

        #expect(!output.contains("123456:telegram-token"))
        #expect(!output.contains("https://example.com/teams/webhook"))
        #expect(output.contains("[REDACTED]"))
    }

    @Test("builds Telegram sendMessage request without leaking token in the body")
    func buildsTelegramRequest() throws {
        let event = CodexNotificationEvent(
            type: .completion,
            title: "Codex 작업 완료",
            message: "테스트 메시지"
        )

        let request = try TelegramRequestBuilder(
            token: "token-abc",
            chatID: "chat-123"
        ).makeRequest(for: event)

        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.telegram.org/bottoken-abc/sendMessage")
        #expect(request.headers["Content-Type"] == "application/json")

        let body = try #require(request.jsonBody)
        #expect(body["chat_id"]?.stringValue == "chat-123")
        #expect(body["text"]?.stringValue?.contains("Codex 작업 완료") == true)
        #expect(body["text"]?.stringValue?.contains("테스트 메시지") == true)
        #expect(!String(decoding: request.body, as: UTF8.self).contains("token-abc"))
    }

    @Test("builds Teams workflow webhook request")
    func buildsTeamsRequest() throws {
        let webhookURL = try #require(URL(string: "https://example.com/workflows/hook"))
        let event = CodexNotificationEvent(
            type: .failed,
            title: "Codex 작업 실패",
            message: "실패 요약"
        )

        let request = try TeamsRequestBuilder(webhookURL: webhookURL).makeRequest(for: event)

        #expect(request.method == "POST")
        #expect(request.url == webhookURL)
        #expect(request.headers["Content-Type"] == "application/json")

        let body = try #require(request.jsonBody)
        #expect(body["text"]?.stringValue?.contains("Codex 작업 실패") == true)
        #expect(body["text"]?.stringValue?.contains("실패 요약") == true)
    }

    @Test("settings store returns defaults and persists routing policy")
    func settingsStorePersistsRoutingPolicy() {
        let suiteName = "CodexNotifierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        #expect(store.load() == .default)

        var settings = CodexNotifierSettings.default
        settings.routingPolicy.set(.macOS, enabled: true, for: .completion)
        settings.telegramTimeoutSeconds = 8

        store.save(settings)

        #expect(store.load().routingPolicy.channels(for: .completion) == [.macOS, .telegram, .teams])
        #expect(store.load().telegramTimeoutSeconds == 8)
    }

    @Test("settings default to focusing the Codex host app from macOS notifications")
    func settingsDefaultToMacOSFocusOnNotificationClick() {
        #expect(CodexNotifierSettings.default.macOSFocusOnNotificationClick)
    }

    @Test("message options default to omitting optional details for every channel")
    func messageOptionsDefaultOff() {
        for channel in NotificationChannel.allCases {
            let options = CodexNotifierSettings.default.messagePolicy.options(for: channel)

            #expect(!options.includeFullMessage)
            #expect(!options.includeFolderName)
            #expect(!options.includeBranchName)
        }
    }

    @Test("settings store preserves legacy settings when newer fields are missing")
    func settingsStorePreservesLegacySettingsWithoutNewerFields() throws {
        struct LegacySettings: Encodable {
            let routingPolicy: RoutingPolicy
            let telegramTimeoutSeconds: TimeInterval
            let teamsTimeoutSeconds: TimeInterval
        }

        let suiteName = "CodexNotifierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var routingPolicy = RoutingPolicy.default
        routingPolicy.set(.macOS, enabled: true, for: .completion)
        let legacy = LegacySettings(
            routingPolicy: routingPolicy,
            telegramTimeoutSeconds: 9,
            teamsTimeoutSeconds: 7
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: "codex-notifier.settings")

        let settings = SettingsStore(defaults: defaults).load()

        #expect(settings.macOSFocusOnNotificationClick)
        #expect(settings.messagePolicy == .default)
        #expect(settings.routingPolicy.channels(for: .completion) == [.macOS, .telegram, .teams])
        #expect(settings.telegramTimeoutSeconds == 9)
        #expect(settings.teamsTimeoutSeconds == 7)
    }

    @Test("message renderer uses the full assistant message and enabled context lines")
    func messageRendererUsesFullMessageAndContext() {
        var policy = NotificationMessagePolicy.default
        policy.set(\.includeFullMessage, enabled: true, for: .telegram)
        policy.set(\.includeFolderName, enabled: true, for: .telegram)
        policy.set(\.includeBranchName, enabled: false, for: .telegram)
        let event = CodexNotificationEvent(
            type: .completion,
            title: "Codex 작업 완료",
            message: "짧은 요약",
            fullMessage: "첫 줄\n둘째 줄",
            context: CodexNotificationContext(folderName: "codex-cli-notify-app", branchName: "main")
        )

        let text = NotificationMessageRenderer().text(
            for: event,
            options: policy.options(for: .telegram)
        )

        #expect(text.contains("Codex 작업 완료"))
        #expect(text.contains("첫 줄\n둘째 줄"))
        #expect(!text.contains("짧은 요약"))
        #expect(text.contains("폴더: codex-cli-notify-app"))
        #expect(!text.contains("브랜치: main"))
    }

    @Test("notification context detector includes folder name and optional branch")
    func notificationContextDetectorIncludesFolderAndBranch() throws {
        let directory = URL(fileURLWithPath: "/tmp/codex-cli-notify-app", isDirectory: true)

        let context = CodexNotificationContextDetector(
            currentDirectoryURL: directory,
            branchNameProvider: { url in
                url.lastPathComponent == "codex-cli-notify-app" ? "feature/message-options" : nil
            }
        ).detect()

        #expect(context.folderName == "codex-cli-notify-app")
        #expect(context.branchName == "feature/message-options")

        let nonGitContext = CodexNotificationContextDetector(
            currentDirectoryURL: directory,
            branchNameProvider: { _ in nil }
        ).detect()

        #expect(nonGitContext.folderName == "codex-cli-notify-app")
        #expect(nonGitContext.branchName == nil)
    }

    @Test("detects JetBrains terminal focus target from environment")
    func detectsJetBrainsTerminalFocusTarget() throws {
        let target = try #require(MacOSFocusTarget.detect(
            environment: [
                "__CFBundleIdentifier": "com.jetbrains.intellij",
                "TERMINAL_EMULATOR": "JetBrains-JediTerm",
                "TERM_SESSION_ID": "jetbrains-session"
            ],
            includeProcessAncestry: false
        ))

        #expect(target.bundleIdentifier == "com.jetbrains.intellij")
        #expect(target.terminalKind == "JetBrains-JediTerm")
        #expect(target.terminalSessionIdentifier == "jetbrains-session")
    }

    @Test("detects VSCode terminal focus target from environment")
    func detectsVSCodeTerminalFocusTarget() throws {
        let target = try #require(MacOSFocusTarget.detect(
            environment: [
                "TERM_PROGRAM": "vscode",
                "TERM_SESSION_ID": "vscode-session"
            ],
            includeProcessAncestry: false
        ))

        #expect(target.bundleIdentifier == "com.microsoft.VSCode")
        #expect(target.terminalKind == "vscode")
        #expect(target.terminalSessionIdentifier == "vscode-session")
    }

    @Test("detects iTerm terminal focus target from environment")
    func detectsITermTerminalFocusTarget() throws {
        let target = try #require(MacOSFocusTarget.detect(
            environment: [
                "TERM_PROGRAM": "iTerm.app",
                "ITERM_SESSION_ID": "iterm-session"
            ],
            includeProcessAncestry: false
        ))

        #expect(target.bundleIdentifier == "com.googlecode.iterm2")
        #expect(target.terminalKind == "iTerm.app")
        #expect(target.terminalSessionIdentifier == "iterm-session")
    }

    @Test("unknown terminal environment has no focus target")
    func unknownTerminalEnvironmentHasNoFocusTarget() {
        #expect(MacOSFocusTarget.detect(environment: ["TERM": "xterm-256color"], includeProcessAncestry: false) == nil)
    }

    @Test("notification envelope decodes wrapped and legacy payloads")
    func notificationEnvelopeDecodesWrappedAndLegacyPayloads() throws {
        let target = MacOSFocusTarget(
            bundleIdentifier: "com.jetbrains.intellij",
            processIdentifier: 44317,
            appName: "IntelliJ IDEA",
            terminalKind: "JetBrains-JediTerm",
            terminalSessionIdentifier: "jetbrains-session"
        )
        let envelope = CodexNotificationEnvelope(
            payload: .object(["type": .string("approval-requested")]),
            focusTarget: target,
            context: CodexNotificationContext(folderName: "codex-cli-notify-app", branchName: "main")
        )
        let wrappedData = try JSONEncoder().encode(envelope)
        let decodedWrapped = try CodexNotificationEnvelope.decode(from: wrappedData)

        #expect(decodedWrapped.payload["type"]?.stringValue == "approval-requested")
        #expect(decodedWrapped.focusTarget == target)
        #expect(decodedWrapped.context?.folderName == "codex-cli-notify-app")
        #expect(decodedWrapped.context?.branchName == "main")

        let legacyData = Data(#"{"status":"failed"}"#.utf8)
        let decodedLegacy = try CodexNotificationEnvelope.decode(from: legacyData)

        #expect(decodedLegacy.payload["status"]?.stringValue == "failed")
        #expect(decodedLegacy.focusTarget == nil)
        #expect(decodedLegacy.context == nil)
    }

    @Test("history store keeps newest entries first and limits failures")
    func historyStoreKeepsNewestEntries() {
        let suiteName = "CodexNotifierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NotificationHistoryStore(defaults: defaults, maxEntries: 2)

        let first = CodexNotificationEvent(type: .completion, title: "first", message: "one")
        let second = CodexNotificationEvent(type: .failed, title: "second", message: "two")
        let third = CodexNotificationEvent(type: .actionRequired, title: "third", message: "three")

        store.appendHistory(NotificationHistoryEntry(event: first, outcomes: []))
        store.appendHistory(NotificationHistoryEntry(event: second, outcomes: []))
        store.appendHistory(NotificationHistoryEntry(event: third, outcomes: []))
        store.appendFailure(FailureLogEntry(channel: .teams, eventType: .failed, statusCode: 500, summary: "one"))
        store.appendFailure(FailureLogEntry(channel: .telegram, eventType: .failed, statusCode: 401, summary: "two"))
        store.appendFailure(FailureLogEntry(channel: .macOS, eventType: .failed, statusCode: nil, summary: "three"))

        #expect(store.loadHistory().map(\.event.title) == ["third", "second"])
        #expect(store.loadFailures().map(\.summary) == ["three", "two"])
    }

    @Test("history store clears failures for recovered channel")
    func historyStoreClearsFailuresForRecoveredChannel() {
        let suiteName = "CodexNotifierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NotificationHistoryStore(defaults: defaults)

        store.appendFailure(FailureLogEntry(channel: .macOS, eventType: .failed, statusCode: nil, summary: "macOS denied"))
        store.appendFailure(FailureLogEntry(channel: .telegram, eventType: .failed, statusCode: 400, summary: "telegram failed"))

        store.clearFailures(for: .macOS)

        #expect(store.loadFailures().map(\.summary) == ["telegram failed"])
    }

    @Test("history store clears failures that have newer successful history")
    func historyStoreClearsFailuresRecoveredByHistory() {
        let suiteName = "CodexNotifierTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NotificationHistoryStore(defaults: defaults)

        let failedAt = Date(timeIntervalSince1970: 1)
        let recoveredAt = Date(timeIntervalSince1970: 2)

        store.appendFailure(FailureLogEntry(recordedAt: failedAt, channel: .macOS, eventType: .failed, statusCode: nil, summary: "macOS denied"))
        store.appendFailure(FailureLogEntry(recordedAt: failedAt, channel: .telegram, eventType: .failed, statusCode: 400, summary: "telegram failed"))
        store.appendHistory(
            NotificationHistoryEntry(
                event: CodexNotificationEvent(receivedAt: recoveredAt, type: .completion, title: "recovered", message: "ok"),
                outcomes: [DeliveryOutcome(channel: .macOS, succeeded: true, summary: "sent")]
            )
        )

        store.clearFailuresResolvedByHistory()

        #expect(store.loadFailures().map(\.summary) == ["telegram failed"])
    }
}
