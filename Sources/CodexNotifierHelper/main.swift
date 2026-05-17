import CodexNotifierCore
import Foundation

@main
struct CodexNotifierHelper {
    static func main() {
        do {
            let invocation = try readInvocation()
            let payload = invocation.payload
            let parsedPayload = try CodexPayloadParser.parse(payload)
            let envelope = CodexNotificationEnvelope(
                payload: parsedPayload,
                focusTarget: MacOSFocusTarget.detect(),
                context: CodexNotificationContextDetector().detect()
            )
            _ = try inboxStore().writePayload(try JSONEncoder().encode(envelope))
            try ensureAppRunning()
            postPayloadNotification()
            forwardPreviousNotifyIfNeeded(invocation.previousNotify, payload: payload)
        } catch {
            FileHandle.standardError.write(Data("codex-notifier-helper: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func readInvocation() throws -> CodexNotifierHelperInvocation {
        try CodexNotifierHelperInvocation.parse(arguments: CommandLine.arguments) {
            FileHandle.standardInput.readDataToEndOfFile()
        }
    }

    private static func forwardPreviousNotifyIfNeeded(_ command: [String]?, payload: Data) {
        guard let command, !command.isEmpty else { return }

        do {
            try runPreviousNotify(command, payload: payload)
        } catch {
            FileHandle.standardError.write(Data("codex-notifier-helper previous notify failed: \(error)\n".utf8))
        }
    }

    private static func runPreviousNotify(_ command: [String], payload: Data) throws {
        guard let executable = command.first else { return }

        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst()) + [String(decoding: payload, as: UTF8.self)]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command + [String(decoding: payload, as: UTF8.self)]
        }

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        try process.run()
        stdinPipe.fileHandleForWriting.write(payload)
        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HelperError.previousNotifyFailed(process.terminationStatus)
        }
    }

    private static func ensureAppRunning() throws {
        if ProcessInfo.processInfo.environment["CODEX_NOTIFIER_SKIP_OPEN"] == "1" {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        if let appPath = ProcessInfo.processInfo.environment["CODEX_NOTIFIER_APP_PATH"], !appPath.isEmpty {
            process.arguments = [appPath]
        } else {
            process.arguments = ["-a", CodexNotifierConstants.appName]
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HelperError.openFailed(process.terminationStatus)
        }
    }

    private static func postPayloadNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(CodexNotifierConstants.payloadCreatedNotification),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func inboxStore() -> InboxStore {
        if let root = ProcessInfo.processInfo.environment["CODEX_NOTIFIER_APP_SUPPORT"], !root.isEmpty {
            return InboxStore(rootDirectory: URL(fileURLWithPath: root, isDirectory: true))
        }

        return InboxStore()
    }
}

private enum HelperError: Error {
    case openFailed(Int32)
    case previousNotifyFailed(Int32)
}
