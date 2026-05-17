import Darwin
import Foundation

public struct MacOSFocusTarget: Codable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let processIdentifier: Int32?
    public let appName: String?
    public let terminalKind: String?
    public let terminalSessionIdentifier: String?

    public init(
        bundleIdentifier: String,
        processIdentifier: Int32? = nil,
        appName: String? = nil,
        terminalKind: String? = nil,
        terminalSessionIdentifier: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.appName = appName
        self.terminalKind = terminalKind
        self.terminalSessionIdentifier = terminalSessionIdentifier
    }

    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processIdentifier: Int32 = getpid(),
        includeProcessAncestry: Bool = true
    ) -> MacOSFocusTarget? {
        let terminalKind = terminalKind(in: environment)
        let terminalSessionIdentifier = terminalSessionIdentifier(in: environment)
        let environmentTarget = focusTargetFromEnvironment(
            environment,
            terminalKind: terminalKind,
            terminalSessionIdentifier: terminalSessionIdentifier
        )

        guard includeProcessAncestry else {
            return environmentTarget
        }

        let ancestryTarget = focusTargetFromProcessAncestry(
            startingAt: processIdentifier,
            preferredBundleIdentifier: environmentTarget?.bundleIdentifier,
            terminalKind: terminalKind,
            terminalSessionIdentifier: terminalSessionIdentifier
        )

        guard let environmentTarget else {
            return ancestryTarget
        }

        guard let ancestryTarget, ancestryTarget.bundleIdentifier == environmentTarget.bundleIdentifier else {
            return environmentTarget
        }

        return MacOSFocusTarget(
            bundleIdentifier: environmentTarget.bundleIdentifier,
            processIdentifier: ancestryTarget.processIdentifier,
            appName: ancestryTarget.appName ?? environmentTarget.appName,
            terminalKind: environmentTarget.terminalKind,
            terminalSessionIdentifier: environmentTarget.terminalSessionIdentifier
        )
    }

    private static func focusTargetFromEnvironment(
        _ environment: [String: String],
        terminalKind: String?,
        terminalSessionIdentifier: String?
    ) -> MacOSFocusTarget? {
        if let bundleIdentifier = nonEmpty(environment["__CFBundleIdentifier"]) {
            return MacOSFocusTarget(
                bundleIdentifier: bundleIdentifier,
                appName: appName(for: bundleIdentifier),
                terminalKind: terminalKind,
                terminalSessionIdentifier: terminalSessionIdentifier
            )
        }

        if nonEmpty(environment["VSCODE_PID"]) != nil {
            return MacOSFocusTarget(
                bundleIdentifier: "com.microsoft.VSCode",
                appName: "Code",
                terminalKind: terminalKind,
                terminalSessionIdentifier: terminalSessionIdentifier
            )
        }

        guard let termProgram = nonEmpty(environment["TERM_PROGRAM"]) else {
            return nil
        }

        let bundleIdentifier: String?
        switch termProgram {
        case "vscode":
            bundleIdentifier = "com.microsoft.VSCode"
        case "Apple_Terminal":
            bundleIdentifier = "com.apple.Terminal"
        case "iTerm.app":
            bundleIdentifier = "com.googlecode.iterm2"
        default:
            bundleIdentifier = nil
        }

        guard let bundleIdentifier else {
            return nil
        }

        return MacOSFocusTarget(
            bundleIdentifier: bundleIdentifier,
            appName: appName(for: bundleIdentifier),
            terminalKind: terminalKind,
            terminalSessionIdentifier: terminalSessionIdentifier
        )
    }

    private static func focusTargetFromProcessAncestry(
        startingAt processIdentifier: Int32,
        preferredBundleIdentifier: String?,
        terminalKind: String?,
        terminalSessionIdentifier: String?
    ) -> MacOSFocusTarget? {
        var currentProcessIdentifier = processIdentifier
        var visitedProcessIdentifiers = Set<Int32>()
        var fallbackTarget: MacOSFocusTarget?

        while let row = ProcessTableRow.current(processIdentifier: currentProcessIdentifier),
              !visitedProcessIdentifiers.contains(currentProcessIdentifier) {
            visitedProcessIdentifiers.insert(currentProcessIdentifier)

            if let target = focusTarget(
                fromCommand: row.command,
                processIdentifier: row.processIdentifier,
                terminalKind: terminalKind,
                terminalSessionIdentifier: terminalSessionIdentifier
            ) {
                if preferredBundleIdentifier == nil || target.bundleIdentifier == preferredBundleIdentifier {
                    return target
                }

                if fallbackTarget == nil {
                    fallbackTarget = target
                }
            }

            guard row.parentProcessIdentifier > 1 else { break }
            currentProcessIdentifier = row.parentProcessIdentifier
        }

        return fallbackTarget
    }

    private static func focusTarget(
        fromCommand command: String,
        processIdentifier: Int32,
        terminalKind: String?,
        terminalSessionIdentifier: String?
    ) -> MacOSFocusTarget? {
        guard let appBundlePath = appBundlePath(in: command),
              appBundlePath != Bundle.main.bundlePath,
              let bundle = Bundle(path: appBundlePath),
              let bundleIdentifier = bundle.bundleIdentifier,
              !ignoredBundleIdentifiers.contains(bundleIdentifier) else {
            return nil
        }

        return MacOSFocusTarget(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            appName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            terminalKind: terminalKind,
            terminalSessionIdentifier: terminalSessionIdentifier
        )
    }

    private static func appBundlePath(in command: String) -> String? {
        guard let range = command.range(of: ".app") else {
            return nil
        }

        let path = String(command[..<range.upperBound])
        return path.hasPrefix("/") ? path : nil
    }

    private static func terminalKind(in environment: [String: String]) -> String? {
        nonEmpty(environment["TERMINAL_EMULATOR"]) ?? nonEmpty(environment["TERM_PROGRAM"])
    }

    private static func terminalSessionIdentifier(in environment: [String: String]) -> String? {
        nonEmpty(environment["TERM_SESSION_ID"]) ?? nonEmpty(environment["ITERM_SESSION_ID"])
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func appName(for bundleIdentifier: String) -> String? {
        switch bundleIdentifier {
        case "com.jetbrains.intellij":
            "IntelliJ IDEA"
        case "com.microsoft.VSCode":
            "Code"
        case "com.apple.Terminal":
            "Terminal"
        case "com.googlecode.iterm2":
            "iTerm2"
        case "com.openai.codex":
            "Codex"
        default:
            nil
        }
    }

    private static var ignoredBundleIdentifiers: Set<String> {
        [
            CodexNotifierConstants.bundleIdentifier,
            "com.openai.sky.CUAService",
            "com.openai.sky.CUAService.cli"
        ]
    }
}

private struct ProcessTableRow {
    let processIdentifier: Int32
    let parentProcessIdentifier: Int32
    let command: String

    static func current(processIdentifier: Int32) -> ProcessTableRow? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(processIdentifier), "-o", "pid=,ppid=,command="]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        return output
            .split(separator: "\n")
            .compactMap(ProcessTableRow.init)
            .first
    }

    init?(_ line: Substring) {
        let parts = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)

        guard parts.count == 3,
              let processIdentifier = Int32(String(parts[0])),
              let parentProcessIdentifier = Int32(String(parts[1])) else {
            return nil
        }

        self.processIdentifier = processIdentifier
        self.parentProcessIdentifier = parentProcessIdentifier
        command = String(parts[2])
    }
}
