import Foundation
import Testing
@testable import CodexNotifierCore

@Suite("Codex session final messages")
struct CodexSessionFinalMessageTests {
    @Test("lookup uses the newest matching cwd rollout and extracts the last final assistant message")
    func lookupUsesNewestMatchingCwdFinalAssistantMessage() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let projectURL = temporaryDirectory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let sessionsRoot = temporaryDirectory.appendingPathComponent("sessions", isDirectory: true)
        let olderRollout = sessionsRoot.appendingPathComponent("2026/05/18/rollout-old.jsonl")
        let newerRollout = sessionsRoot.appendingPathComponent("2026/05/18/rollout-new.jsonl")

        try writeRollout(
            olderRollout,
            modifiedAt: Date(timeIntervalSince1970: 10),
            lines: [
                sessionMeta(cwd: projectURL.path),
                assistantMessage(phase: "final", text: "이전 final")
            ]
        )
        try writeRollout(
            newerRollout,
            modifiedAt: Date(timeIntervalSince1970: 20),
            lines: [
                sessionMeta(cwd: projectURL.path),
                assistantMessage(phase: "commentary", text: "중간 안내"),
                toolOutput(phase: "final", text: "도구 출력"),
                assistantMessage(phase: "final", text: "첫 final"),
                assistantMessage(phase: "final_answer", text: "마지막 final")
            ]
        )

        let message = CodexSessionFinalMessageLookup(sessionsRootURL: sessionsRoot)
            .latestFinalAssistantMessage(projectPath: projectURL.path)

        #expect(message == "마지막 final")
    }

    @Test("lookup ignores rollout files from other cwd values")
    func lookupIgnoresOtherCwdFiles() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let projectURL = temporaryDirectory.appendingPathComponent("Project", isDirectory: true)
        let otherURL = temporaryDirectory.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)
        let sessionsRoot = temporaryDirectory.appendingPathComponent("sessions", isDirectory: true)
        let rollout = sessionsRoot.appendingPathComponent("2026/05/18/rollout-other.jsonl")

        try writeRollout(
            rollout,
            modifiedAt: Date(timeIntervalSince1970: 10),
            lines: [
                sessionMeta(cwd: otherURL.path),
                assistantMessage(phase: "final", text: "다른 프로젝트 final")
            ]
        )

        let message = CodexSessionFinalMessageLookup(sessionsRootURL: sessionsRoot)
            .latestFinalAssistantMessage(projectPath: projectURL.path)

        #expect(message == nil)
    }

    @Test("enricher uses the session final message only when a routed channel requests it")
    func enricherUsesSessionFinalMessageOnlyWhenRequested() {
        var settings = CodexNotifierSettings.default
        settings.routingPolicy.set(.telegram, enabled: true, for: .completion)
        settings.messagePolicy.set(\.includeFullMessage, enabled: true, for: .telegram)

        var requestedProjectPaths: [String] = []
        let enricher = CodexNotificationFinalMessageEnricher { projectPath in
            requestedProjectPaths.append(projectPath)
            return "세션의 마지막 마무리 메시지"
        }
        let event = CodexNotificationEvent(
            type: .completion,
            title: "Codex 작업 완료",
            message: "Codex 작업이 완료되었습니다.",
            context: CodexNotificationContext(
                folderName: "Project",
                branchName: "main",
                projectPath: "/tmp/Project"
            )
        )

        let enriched = enricher.enrich(event, settings: settings)

        #expect(enriched.fullMessage == "세션의 마지막 마무리 메시지")
        #expect(enriched.id == event.id)
        #expect(enriched.receivedAt == event.receivedAt)
        #expect(requestedProjectPaths == ["/tmp/Project"])
    }

    @Test("enricher keeps an existing full message")
    func enricherKeepsExistingFullMessage() {
        var settings = CodexNotifierSettings.default
        settings.routingPolicy.set(.telegram, enabled: true, for: .completion)
        settings.messagePolicy.set(\.includeFullMessage, enabled: true, for: .telegram)

        var lookupCount = 0
        let enricher = CodexNotificationFinalMessageEnricher { _ in
            lookupCount += 1
            return "세션 final"
        }
        let event = CodexNotificationEvent(
            type: .completion,
            title: "Codex 작업 완료",
            message: "요약",
            fullMessage: "payload 전문",
            context: CodexNotificationContext(folderName: "Project", branchName: nil, projectPath: "/tmp/Project")
        )

        let enriched = enricher.enrich(event, settings: settings)

        #expect(enriched.fullMessage == "payload 전문")
        #expect(lookupCount == 0)
    }

    @Test("enricher does not read sessions when the routed channel omits the final message")
    func enricherSkipsLookupWhenFinalMessageOptionIsOff() {
        var settings = CodexNotifierSettings.default
        settings.routingPolicy.set(.telegram, enabled: true, for: .completion)

        var lookupCount = 0
        let enricher = CodexNotificationFinalMessageEnricher { _ in
            lookupCount += 1
            return "세션 final"
        }
        let event = CodexNotificationEvent(
            type: .completion,
            title: "Codex 작업 완료",
            message: "요약",
            context: CodexNotificationContext(folderName: "Project", branchName: nil, projectPath: "/tmp/Project")
        )

        let enriched = enricher.enrich(event, settings: settings)

        #expect(enriched.fullMessage == nil)
        #expect(lookupCount == 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeRollout(_ url: URL, modifiedAt: Date, lines: [String]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }

    private func sessionMeta(cwd: String) -> String {
        #"{"type":"session_meta","payload":{"cwd":"\#(cwd)"}}"#
    }

    private func assistantMessage(phase: String, text: String) -> String {
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"\#(phase)","content":[{"type":"output_text","text":"\#(text)"}]}}"#
    }

    private func toolOutput(phase: String, text: String) -> String {
        #"{"type":"response_item","payload":{"type":"function_call_output","phase":"\#(phase)","content":[{"type":"output_text","text":"\#(text)"}]}}"#
    }
}
