import Foundation
import Testing
@testable import CodexNotifierCore

@Suite("Codex CLI integration")
struct CodexCLIIntegrationTests {
    @Test("installer adds Codex Notifier helper when config has no notify")
    func installerAddsHelperNotify() throws {
        let fixture = try IntegrationFixture()
        try fixture.writeHelper()
        try fixture.writeConfig(
            """
            model = "gpt-5.5"

            [features]
            multi_agent = true
            """
        )

        let result = try fixture.installer.install()
        let updatedConfig = try String(contentsOf: fixture.configURL, encoding: .utf8)
        let parsedNotify = try CodexCLIConfigDocument.topLevelNotify(in: updatedConfig)
        let notify = try #require(parsedNotify)

        #expect(result.changed)
        #expect(result.previousNotify == nil)
        #expect(notify == [fixture.helperURL.path])
        #expect(updatedConfig.contains("[features]"))
        #expect(fixture.backupExists())
    }

    @Test("installer preserves an existing notify command behind the helper")
    func installerPreservesExistingNotify() throws {
        let fixture = try IntegrationFixture()
        try fixture.writeHelper()
        try fixture.writeConfig(
            """
            model = "gpt-5.5"
            notify = ["/usr/bin/osascript", "-e", "display notification \\"done\\""]

            [features]
            multi_agent = true
            """
        )

        let result = try fixture.installer.install()
        let updatedConfig = try String(contentsOf: fixture.configURL, encoding: .utf8)
        let parsedNotify = try CodexCLIConfigDocument.topLevelNotify(in: updatedConfig)
        let notify = try #require(parsedNotify)

        #expect(result.changed)
        #expect(result.previousNotify == ["/usr/bin/osascript", "-e", "display notification \"done\""])
        #expect(notify.first == fixture.helperURL.path)
        #expect(try CodexNotifyCommand.previousNotify(from: notify) == result.previousNotify)
        #expect(fixture.backupExists())
    }

    @Test("installer does not duplicate an existing helper notify")
    func installerDoesNotDuplicateHelperNotify() throws {
        let fixture = try IntegrationFixture()
        try fixture.writeHelper()
        let existingNotify = CodexNotifyCommand.make(
            helperPath: fixture.helperURL.path,
            previousNotify: ["/bin/echo", "done"]
        )
        try fixture.writeConfig("notify = \(try CodexNotifyCommand.encode(existingNotify))\n")

        let result = try fixture.installer.install()
        let updatedConfig = try String(contentsOf: fixture.configURL, encoding: .utf8)
        let parsedNotify = try CodexCLIConfigDocument.topLevelNotify(in: updatedConfig)
        let notify = try #require(parsedNotify)

        #expect(!result.changed)
        #expect(notify == existingNotify)
        #expect(!fixture.backupExists())
    }

    @Test("installer treats nested previous notify helper as already connected")
    func installerDetectsNestedHelperNotify() throws {
        let fixture = try IntegrationFixture()
        try fixture.writeHelper()
        let existingNotify = [
            "/tmp/codex-wrapper",
            "turn-ended",
            "--previous-notify",
            try CodexNotifyCommand.encode([fixture.helperURL.path])
        ]
        try fixture.writeConfig("notify = \(try CodexNotifyCommand.encode(existingNotify))\n")

        let result = try fixture.installer.install()
        let updatedConfig = try String(contentsOf: fixture.configURL, encoding: .utf8)
        let parsedNotify = try CodexCLIConfigDocument.topLevelNotify(in: updatedConfig)
        let notify = try #require(parsedNotify)

        #expect(!result.changed)
        #expect(notify == existingNotify)
        #expect(fixture.installer.status().state == .connected)
        #expect(!fixture.backupExists())
    }

    @Test("installer restores the latest config backup")
    func installerRestoresLatestBackup() throws {
        let fixture = try IntegrationFixture()
        try fixture.writeConfig("notify = [\"/tmp/current\"]\n")
        try fixture.writeBackup(timestamp: "20260517-170000", text: "notify = [\"/tmp/old\"]\n")
        try fixture.writeBackup(timestamp: "20260517-180000", text: "notify = [\"/tmp/latest\"]\n")

        let restoredURL = try fixture.installer.restoreLatestBackup()
        let restoredConfig = try String(contentsOf: fixture.configURL, encoding: .utf8)

        #expect(restoredURL.lastPathComponent == "config.toml")
        #expect(restoredURL.deletingLastPathComponent().lastPathComponent == "codex-notifier-20260517-180000")
        #expect(restoredConfig == "notify = [\"/tmp/latest\"]\n")
    }

    @Test("helper invocation separates previous notify arguments from payload")
    func helperInvocationParsesPreviousNotify() throws {
        let invocation = try CodexNotifierHelperInvocation.parse(
            arguments: [
                "codex-notifier-helper",
                "--previous-notify",
                "[\"/bin/echo\",\"done\"]",
                #"{"type":"approval-requested"}"#
            ],
            stdinData: Data()
        )

        #expect(invocation.previousNotify == ["/bin/echo", "done"])
        #expect(String(decoding: invocation.payload, as: UTF8.self) == #"{"type":"approval-requested"}"#)
    }
}

private struct IntegrationFixture {
    let rootURL: URL
    let configURL: URL
    let helperURL: URL
    let installer: CodexCLIConfigInstaller

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNotifierTests.\(UUID().uuidString)", isDirectory: true)
        configURL = rootURL.appendingPathComponent(".codex/config.toml")
        helperURL = rootURL.appendingPathComponent(
            "Applications/Codex Notifier.app/Contents/MacOS/codex-notifier-helper"
        )
        installer = CodexCLIConfigInstaller(
            configURL: configURL,
            helperPath: helperURL.path,
            timestampProvider: { "20260517-175900" }
        )
    }

    func writeHelper() throws {
        try FileManager.default.createDirectory(
            at: helperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: helperURL)
    }

    func writeConfig(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func backupExists() -> Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    func writeBackup(timestamp: String, text: String) throws {
        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("backups/codex-notifier-\(timestamp)/config.toml")
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: backupURL, atomically: true, encoding: .utf8)
    }

    private var backupURL: URL {
        configURL.deletingLastPathComponent()
            .appendingPathComponent("backups/codex-notifier-20260517-175900/config.toml")
    }
}
