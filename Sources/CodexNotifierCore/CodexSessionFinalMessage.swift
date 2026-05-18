import Foundation

public struct CodexSessionFinalMessageLookup {
    private let sessionsRootURL: URL
    private let fileManager: FileManager

    public init(
        sessionsRootURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.sessionsRootURL = sessionsRootURL
        self.fileManager = fileManager
    }

    public func latestFinalAssistantMessage(projectPath: String) -> String? {
        let normalizedProjectPath = normalizedPath(projectPath)

        for rolloutURL in rolloutFileURLsByNewestFirst() {
            guard let cwd = rolloutCWD(in: rolloutURL),
                  normalizedPath(cwd) == normalizedProjectPath else {
                continue
            }

            return lastFinalAssistantMessage(in: rolloutURL)
        }

        return nil
    }

    private func rolloutFileURLsByNewestFirst() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rolloutURLs = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl" else {
                return nil
            }

            return url
        }

        return rolloutURLs.sorted { lhs, rhs in
            modificationDate(of: lhs) > modificationDate(of: rhs)
        }
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func rolloutCWD(in url: URL) -> String? {
        for line in lines(in: url) {
            guard let object = jsonObject(from: line),
                  object["type"]?.stringValue == "session_meta",
                  let cwd = object["payload"]?.objectValue?["cwd"]?.stringValue,
                  !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            return cwd
        }

        return nil
    }

    private func lastFinalAssistantMessage(in url: URL) -> String? {
        var lastMessage: String?

        for line in lines(in: url) {
            guard let object = jsonObject(from: line),
                  object["type"]?.stringValue == "response_item",
                  let payload = object["payload"]?.objectValue,
                  payload["type"]?.stringValue == "message",
                  payload["role"]?.stringValue == "assistant",
                  isFinalPhase(payload["phase"]?.stringValue),
                  let message = outputText(from: payload["content"]) else {
                continue
            }

            lastMessage = message
        }

        return lastMessage
    }

    private func lines(in url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func jsonObject(from line: String) -> [String: JSONValue]? {
        try? CodexPayloadParser.parse(line).objectValue
    }

    private func isFinalPhase(_ phase: String?) -> Bool {
        guard let phase = phase?.lowercased() else { return false }

        // Codex CLI 세션 로그는 사용자가 보는 마지막 답변 phase 이름을 두 형태로 기록해 왔다.
        return phase == "final" || phase == "final_answer"
    }

    private func outputText(from value: JSONValue?) -> String? {
        guard let value else { return nil }

        let text: String?
        switch value {
        case let .string(value):
            text = value
        case let .array(values):
            let parts = values.compactMap { outputText(from: $0) }
            text = parts.isEmpty ? nil : parts.joined(separator: "\n")
        case let .object(object):
            if object["type"]?.stringValue == "output_text" {
                text = object["text"]?.stringValue
            } else {
                text = outputText(from: object["content"])
            }
        case .number, .bool, .null:
            text = nil
        }

        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}

public struct CodexNotificationFinalMessageEnricher {
    public typealias FinalMessageProvider = (String) -> String?

    private let finalMessageProvider: FinalMessageProvider

    public init(
        finalMessageProvider: @escaping FinalMessageProvider = {
            CodexSessionFinalMessageLookup().latestFinalAssistantMessage(projectPath: $0)
        }
    ) {
        self.finalMessageProvider = finalMessageProvider
    }

    public func enrich(_ event: CodexNotificationEvent, settings: CodexNotifierSettings) -> CodexNotificationEvent {
        guard event.fullMessage == nil,
              shouldIncludeFullMessage(for: event.type, settings: settings),
              let projectPath = event.context?.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectPath.isEmpty else {
            return event
        }

        return event.addingFullMessageIfMissing(finalMessageProvider(projectPath))
    }

    private func shouldIncludeFullMessage(
        for eventType: CodexEventType,
        settings: CodexNotifierSettings
    ) -> Bool {
        settings.routingPolicy.channels(for: eventType).contains { channel in
            settings.messagePolicy.options(for: channel).includeFullMessage
        }
    }
}
