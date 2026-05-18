import CodexNotifierCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @State private var selectedItem: SettingsSidebarItem? = .codex

    var body: some View {
        NavigationSplitView {
            List(SettingsSidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
                    .padding(.vertical, 3)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                switch selectedItem ?? .codex {
                case .codex:
                    codexDetail
                case .macOS:
                    channelDetail(.macOS)
                case .telegram:
                    channelDetail(.telegram)
                case .teams:
                    channelDetail(.teams)
                case .diagnostics:
                    diagnosticsDetail
                }
            }
            .scrollIndicators(.visible)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("설정")
        .task {
            await controller.refreshMacOSAuthorizationStatus()
            controller.refreshCodexIntegrationStatus()
        }
    }

    private var codexDetail: some View {
        let status = controller.codexIntegrationStatus

        return detailContainer {
            detailHeader(
                title: "Codex 연결",
                subtitle: status.detail,
                statusText: status.summary,
                status: codexStatus(status.state)
            )

            if let issue = controller.codexIntegrationIssue {
                issueBanner(SettingsChannelIssue(summary: issue, statusCode: nil))
            }

            if let message = controller.codexIntegrationMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            GroupBox("CLI 설정") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("config.toml") {
                        Text(status.configPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    LabeledContent("Helper") {
                        Text(status.helperPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 10) {
                        Button("자동 설정") {
                            controller.configureCodexCLI()
                        }
                        .disabled(status.state == .appLocationRequired)

                        Button("설정 복구") {
                            controller.restoreCodexCLIConfig()
                        }

                        Button("Helper 경로 복사") {
                            controller.copyCodexHelperPath()
                        }

                        Button("Finder에서 보기") {
                            controller.openCodexConfigInFinder()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private func channelDetail(_ channel: NotificationChannel) -> some View {
        let state = detailState(for: channel)

        return detailContainer {
            detailHeader(
                title: "\(channel.displayName) 설정",
                subtitle: state.description,
                statusText: state.statusText,
                status: state.status
            )

            GroupBox("사용 여부") {
                Toggle("사용하기", isOn: channelEnabledBinding(channel))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            if let latestError = state.latestError {
                issueBanner(latestError)
            }

            GroupBox("채널 설정") {
                VStack(alignment: .leading, spacing: 14) {
                    switch channel {
                    case .macOS:
                        macOSControls(state)
                    case .telegram:
                        telegramControls
                    case .teams:
                        teamsControls
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("이벤트 라우팅") {
                VStack(alignment: .leading, spacing: 12) {
                    routeToggle("완료", eventType: .completion, channel: channel)
                    routeToggle("입력 필요", eventType: .actionRequired, channel: channel)
                    routeToggle("실패", eventType: .failed, channel: channel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("메시지 구성") {
                VStack(alignment: .leading, spacing: 12) {
                    messageOptionToggle("마무리 메시지", option: \.includeFullMessage, channel: channel)
                    messageOptionToggle("폴더명", option: \.includeFolderName, channel: channel)
                    messageOptionToggle("브랜치", option: \.includeBranchName, channel: channel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("최근 에러") {
                channelFailures(state.recentFailures)
                    .padding(.vertical, 2)
            }
        }
    }

    private var diagnosticsDetail: some View {
        detailContainer {
            detailHeader(
                title: "진단",
                subtitle: "Helper 경로와 앱 전역 오류를 확인합니다.",
                statusText: controller.failures.isEmpty ? "최근 실패 없음" : "실패 기록 있음",
                status: controller.failures.isEmpty ? .connected : .failed
            )

            if let lastError = controller.lastError {
                issueBanner(SettingsChannelIssue(summary: lastError, statusCode: nil))
            }

            GroupBox("Helper") {
                Text(controller.helperStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            GroupBox("최근 실패 로그") {
                if controller.failures.isEmpty {
                    emptyFailureText
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(controller.failures.prefix(5)) { failure in
                            failureRow(failure, showsChannel: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func detailContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            content()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func detailHeader(
        title: String,
        subtitle: String,
        statusText: String,
        status: SettingsChannelStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.title2.weight(.semibold))
                statusBadge(statusText, status: status)
                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBadge(_ text: String, status: SettingsChannelStatus) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusForegroundColor(status))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(statusBackgroundColor(status), in: Capsule())
    }

    private func issueBanner(_ issue: SettingsChannelIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.summary)
                    .font(.callout.weight(.medium))
                if let statusCode = issue.statusCode {
                    Text("HTTP \(statusCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func macOSControls(_ state: SettingsChannelDetailState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("권한 상태") {
                Text(state.statusText)
                    .foregroundStyle(statusForegroundColor(state.status))
            }

            Toggle("알림 클릭 시 원래 앱으로 이동", isOn: macOSFocusBinding)

            HStack(spacing: 10) {
                if state.showsMacOSPermissionRequest {
                    Button("권한 요청") {
                        controller.requestMacOSPermission()
                    }
                }

                Button("테스트 발송") {
                    Task { await controller.sendTest(to: .macOS) }
                }
            }
        }
    }

    private var telegramControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Telegram Bot Token", text: $controller.telegramBotToken)
            TextField("Telegram Chat ID", text: $controller.telegramChatID)
            Stepper(
                "Timeout \(Int(controller.settings.telegramTimeoutSeconds))초",
                value: timeoutBinding(\.telegramTimeoutSeconds),
                in: 1...60,
                step: 1
            )
            credentialActions(channel: .telegram)
        }
    }

    private var teamsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Teams Workflow Webhook URL", text: $controller.teamsWebhookURL)
            Stepper(
                "Timeout \(Int(controller.settings.teamsTimeoutSeconds))초",
                value: timeoutBinding(\.teamsTimeoutSeconds),
                in: 1...60,
                step: 1
            )
            credentialActions(channel: .teams)
        }
    }

    private func credentialActions(channel: NotificationChannel) -> some View {
        HStack(spacing: 10) {
            Button("비밀값 저장") {
                controller.saveCredentials()
            }

            Button("테스트 발송") {
                Task { await controller.sendTest(to: channel) }
            }
        }
    }

    private func channelFailures(_ failures: [FailureLogEntry]) -> some View {
        Group {
            if failures.isEmpty {
                emptyFailureText
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(failures) { failure in
                        failureRow(failure, showsChannel: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyFailureText: some View {
        Text("최근 에러 없음")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func failureRow(_ failure: FailureLogEntry, showsChannel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(failureTitle(failure, showsChannel: showsChannel))
                .font(.callout.weight(.medium))
            Text(failure.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func failureTitle(_ failure: FailureLogEntry, showsChannel: Bool) -> String {
        let eventText = eventTitle(for: failure.eventType)
        guard showsChannel else {
            return eventText
        }
        return "\(failure.channel.displayName) / \(eventText)"
    }

    private func routeToggle(_ title: String, eventType: CodexEventType, channel: NotificationChannel) -> some View {
        Toggle(title, isOn: routeBinding(eventType: eventType, channel: channel))
    }

    private func routeBinding(eventType: CodexEventType, channel: NotificationChannel) -> Binding<Bool> {
        Binding {
            controller.settings.routingPolicy.channels(for: eventType).contains(channel)
        } set: { enabled in
            controller.updateRoute(eventType: eventType, channel: channel, enabled: enabled)
        }
    }

    private func channelEnabledBinding(_ channel: NotificationChannel) -> Binding<Bool> {
        Binding {
            controller.settings.routingPolicy.isChannelEnabled(channel)
        } set: { enabled in
            controller.updateChannel(channel, enabled: enabled)
        }
    }

    private func messageOptionToggle(
        _ title: String,
        option: WritableKeyPath<NotificationMessageOptions, Bool>,
        channel: NotificationChannel
    ) -> some View {
        Toggle(title, isOn: messageOptionBinding(option, channel: channel))
    }

    private func messageOptionBinding(
        _ option: WritableKeyPath<NotificationMessageOptions, Bool>,
        channel: NotificationChannel
    ) -> Binding<Bool> {
        Binding {
            controller.settings.messagePolicy.options(for: channel)[keyPath: option]
        } set: { enabled in
            controller.updateMessageOption(option, channel: channel, enabled: enabled)
        }
    }

    private func timeoutBinding(_ keyPath: WritableKeyPath<CodexNotifierSettings, TimeInterval>) -> Binding<Double> {
        Binding {
            controller.settings[keyPath: keyPath]
        } set: { value in
            controller.settings[keyPath: keyPath] = value
            controller.saveSettings()
        }
    }

    private var macOSFocusBinding: Binding<Bool> {
        Binding {
            controller.settings.macOSFocusOnNotificationClick
        } set: { enabled in
            controller.settings.macOSFocusOnNotificationClick = enabled
            controller.saveSettings()
        }
    }

    private func detailState(for channel: NotificationChannel) -> SettingsChannelDetailState {
        SettingsChannelDetailState.make(
            channel: channel,
            routingPolicy: controller.settings.routingPolicy,
            macOSAuthorizationStatus: controller.macOSAuthorizationStatus,
            telegramBotToken: controller.telegramBotToken,
            telegramChatID: controller.telegramChatID,
            teamsWebhookURL: controller.teamsWebhookURL,
            failures: controller.failures
        )
    }

    private func statusForegroundColor(_ status: SettingsChannelStatus) -> Color {
        switch status {
        case .unused:
            Color(nsColor: .secondaryLabelColor)
        case .connected:
            .green
        case .needsSetup:
            .orange
        case .failed:
            .red
        }
    }

    private func statusBackgroundColor(_ status: SettingsChannelStatus) -> Color {
        statusForegroundColor(status).opacity(0.12)
    }

    private func codexStatus(_ state: CodexCLIIntegrationStatus.State) -> SettingsChannelStatus {
        switch state {
        case .connected:
            .connected
        case .needsSetup, .appLocationRequired:
            .needsSetup
        case .invalidConfig:
            .failed
        }
    }

    private func eventTitle(for eventType: CodexEventType) -> String {
        switch eventType {
        case .completion:
            "완료"
        case .actionRequired:
            "입력 필요"
        case .failed:
            "실패"
        }
    }
}
