import Foundation

public struct NotificationMessageRenderer: Sendable {
    public init() {}

    public func text(for event: CodexNotificationEvent, options: NotificationMessageOptions) -> String {
        [event.title, body(for: event, options: options)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public func body(for event: CodexNotificationEvent, options: NotificationMessageOptions) -> String {
        ([messageBody(for: event, options: options)] + contextLines(for: event, options: options))
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func messageBody(for event: CodexNotificationEvent, options: NotificationMessageOptions) -> String {
        if options.includeFullMessage,
           let fullMessage = event.fullMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullMessage.isEmpty {
            return fullMessage
        }

        return event.message
    }

    private func contextLines(
        for event: CodexNotificationEvent,
        options: NotificationMessageOptions
    ) -> [String] {
        var lines: [String] = []

        if options.includeFolderName, let folderName = nonEmpty(event.context?.folderName) {
            lines.append("폴더: \(folderName)")
        }

        if options.includeBranchName, let branchName = nonEmpty(event.context?.branchName) {
            lines.append("브랜치: \(branchName)")
        }

        return lines
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

public struct CodexNotificationContextDetector: Sendable {
    public typealias BranchNameProvider = @Sendable (URL) -> String?

    private let currentDirectoryURL: URL
    private let branchNameProvider: BranchNameProvider

    public init(
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        branchNameProvider: @escaping BranchNameProvider = CodexNotificationContextDetector.gitBranchName
    ) {
        self.currentDirectoryURL = currentDirectoryURL
        self.branchNameProvider = branchNameProvider
    }

    public func detect() -> CodexNotificationContext {
        CodexNotificationContext(
            folderName: folderName(in: currentDirectoryURL),
            branchName: branchNameProvider(currentDirectoryURL),
            projectPath: projectPath(in: currentDirectoryURL)
        )
    }

    private func folderName(in url: URL) -> String? {
        let folderName = url.standardizedFileURL.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folderName.isEmpty ? nil : folderName
    }

    private func projectPath(in url: URL) -> String? {
        let path = url.standardizedFileURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    public static func gitBranchName(at directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path, "symbolic-ref", "--short", "HEAD"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let branchName = String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return branchName.isEmpty ? nil : branchName
    }
}
