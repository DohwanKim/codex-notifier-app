import Foundation

public struct CodexCLIIntegrationStatus: Equatable {
    public enum State: Equatable {
        case connected
        case needsSetup
        case appLocationRequired
        case invalidConfig
    }

    public let state: State
    public let summary: String
    public let detail: String
    public let configPath: String
    public let helperPath: String
}

public struct CodexCLIConfigInstallResult: Equatable {
    public let changed: Bool
    public let previousNotify: [String]?
    public let backupURL: URL?
}

public struct CodexCLIConfigInstaller {
    public static let defaultHelperPath = "/Applications/Codex Notifier.app/Contents/MacOS/codex-notifier-helper"

    // Codex는 사용자 단위 설정을 ~/.codex/config.toml에서 읽고, notify는 전역 top-level 키로 해석한다.
    // 프로젝트/프로필별 설정까지 자동 변경하면 사용자가 의도한 우선순위를 깨뜨릴 수 있으므로 이 installer는
    // 명시적으로 전달된 단일 config 파일의 top-level notify만 확인하고 수정한다.
    private let configURL: URL
    private let helperPath: String
    private let fileManager: FileManager
    private let timestampProvider: () -> String

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml"),
        helperPath: String = CodexCLIConfigInstaller.defaultHelperPath,
        fileManager: FileManager = .default,
        timestampProvider: @escaping () -> String = CodexCLIConfigInstaller.makeTimestamp
    ) {
        self.configURL = configURL
        self.helperPath = helperPath
        self.fileManager = fileManager
        self.timestampProvider = timestampProvider
    }

    public func status() -> CodexCLIIntegrationStatus {
        guard fileManager.fileExists(atPath: helperPath) else {
            return CodexCLIIntegrationStatus(
                state: .appLocationRequired,
                summary: "/Applications 설치 필요",
                detail: "Codex notify 설정은 고정된 helper 경로를 사용하므로 앱을 /Applications에 설치해 주세요.",
                configPath: configURL.path,
                helperPath: helperPath
            )
        }

        guard fileManager.fileExists(atPath: configURL.path) else {
            return CodexCLIIntegrationStatus(
                state: .needsSetup,
                summary: "Codex 설정 필요",
                detail: "~/.codex/config.toml이 아직 없습니다. 자동 설정을 실행하면 파일을 생성합니다.",
                configPath: configURL.path,
                helperPath: helperPath
            )
        }

        do {
            let text = try String(contentsOf: configURL, encoding: .utf8)
            let notify = try CodexCLIConfigDocument.topLevelNotify(in: text)
            let isConnected = notify.map { CodexNotifyCommand.containsHelper(helperPath, in: $0) } ?? false

            return CodexCLIIntegrationStatus(
                state: isConnected ? .connected : .needsSetup,
                summary: isConnected ? "연결됨" : "Codex 설정 필요",
                detail: isConnected
                    ? "Codex notify가 Codex Notifier helper로 연결되어 있습니다."
                    : "자동 설정을 실행하면 기존 notify를 보존하면서 Codex Notifier helper를 등록합니다.",
                configPath: configURL.path,
                helperPath: helperPath
            )
        } catch {
            return CodexCLIIntegrationStatus(
                state: .invalidConfig,
                summary: "설정 확인 실패",
                detail: "config.toml의 notify 값을 읽지 못했습니다: \(error)",
                configPath: configURL.path,
                helperPath: helperPath
            )
        }
    }

    public func install() throws -> CodexCLIConfigInstallResult {
        guard fileManager.fileExists(atPath: helperPath) else {
            throw CodexCLIConfigInstallerError.helperMissing(helperPath)
        }

        let originalText: String
        let configExisted = fileManager.fileExists(atPath: configURL.path)

        if configExisted {
            originalText = try String(contentsOf: configURL, encoding: .utf8)
        } else {
            originalText = ""
        }

        let edit = try CodexCLIConfigDocument.installingNotifier(
            helperPath: helperPath,
            in: originalText
        )

        guard edit.changed else {
            return CodexCLIConfigInstallResult(
                changed: false,
                previousNotify: edit.previousNotify,
                backupURL: nil
            )
        }

        // config.toml은 사용자의 다른 Codex 설정을 함께 담는 파일이므로, notify 한 줄만 바꾸더라도
        // 되돌릴 수 있도록 원본 전체를 timestamp가 있는 백업 디렉터리에 먼저 저장한다.
        let backupURL = configExisted ? try writeBackup(originalText) : nil
        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try edit.text.write(to: configURL, atomically: true, encoding: .utf8)
        _ = try CodexCLIConfigDocument.topLevelNotify(in: edit.text)

        return CodexCLIConfigInstallResult(
            changed: true,
            previousNotify: edit.previousNotify,
            backupURL: backupURL
        )
    }

    public func restoreLatestBackup() throws -> URL {
        let backupsURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)

        let backupDirectories = try fileManager.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("codex-notifier-") }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard let backupConfigURL = backupDirectories
            .map({ $0.appendingPathComponent("config.toml") })
            .first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw CodexCLIConfigInstallerError.backupMissing
        }

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.removeItem(at: configURL)
        }
        try fileManager.copyItem(at: backupConfigURL, to: configURL)
        return backupConfigURL
    }

    private func writeBackup(_ text: String) throws -> URL {
        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("backups/codex-notifier-\(timestampProvider())", isDirectory: true)
            .appendingPathComponent("config.toml")

        try fileManager.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: backupURL, atomically: true, encoding: .utf8)
        return backupURL
    }

    public static func makeTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

public enum CodexCLIConfigInstallerError: LocalizedError {
    case helperMissing(String)
    case backupMissing

    public var errorDescription: String? {
        switch self {
        case .helperMissing(let path):
            "Codex Notifier helper를 찾을 수 없습니다: \(path)"
        case .backupMissing:
            "복구할 Codex Notifier config.toml 백업이 없습니다."
        }
    }
}

public struct CodexNotifierHelperInvocation: Equatable {
    public let payload: Data
    public let previousNotify: [String]?

    public static func parse(arguments: [String], stdinData: Data) throws -> CodexNotifierHelperInvocation {
        try parse(arguments: arguments) { stdinData }
    }

    public static func parse(
        arguments: [String],
        stdinDataProvider: () throws -> Data
    ) throws -> CodexNotifierHelperInvocation {
        var index = 1
        var payloadArguments: [String] = []
        var previousNotify: [String]?

        while index < arguments.count {
            let argument = arguments[index]

            if argument == CodexNotifyCommand.previousNotifyFlag {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CodexNotifierHelperInvocationError.missingPreviousNotifyValue
                }
                previousNotify = try CodexNotifyCommand.decode(arguments[valueIndex])
                index += 2
            } else {
                payloadArguments.append(argument)
                index += 1
            }
        }

        if !payloadArguments.isEmpty {
            return CodexNotifierHelperInvocation(
                payload: Data(payloadArguments.joined(separator: " ").utf8),
                previousNotify: previousNotify
            )
        }

        let stdinPayload = try stdinDataProvider()
        guard !stdinPayload.isEmpty else {
            throw CodexNotifierHelperInvocationError.missingPayload
        }

        return CodexNotifierHelperInvocation(
            payload: stdinPayload,
            previousNotify: previousNotify
        )
    }
}

public enum CodexNotifierHelperInvocationError: LocalizedError {
    case missingPayload
    case missingPreviousNotifyValue

    public var errorDescription: String? {
        switch self {
        case .missingPayload:
            "Codex notify payload가 없습니다."
        case .missingPreviousNotifyValue:
            "\(CodexNotifyCommand.previousNotifyFlag) 값이 없습니다."
        }
    }
}

enum CodexCLIConfigDocument {
    struct EditResult {
        let text: String
        let changed: Bool
        let previousNotify: [String]?
    }

    static func topLevelNotify(in text: String) throws -> [String]? {
        let lines = splitLines(text)
        guard let index = topLevelNotifyLineIndex(in: lines) else {
            return nil
        }

        let line = lines[index]
        guard let assignmentIndex = line.firstIndex(of: "=") else {
            throw CodexCLIConfigDocumentError.invalidNotifyValue
        }

        let value = uncommentedValue(String(line[line.index(after: assignmentIndex)...]))
        return try CodexNotifyCommand.decode(value)
    }

    static func installingNotifier(helperPath: String, in text: String) throws -> EditResult {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let notify = CodexNotifyCommand.make(helperPath: helperPath, previousNotify: nil)
            return EditResult(
                text: "notify = \(try CodexNotifyCommand.encode(notify))\n",
                changed: true,
                previousNotify: nil
            )
        }

        var lines = splitLines(text)
        let existingNotify = try topLevelNotify(in: text)

        // 다른 notify 래퍼가 이미 Codex Notifier helper를 --previous-notify 등으로 품고 있을 수 있다.
        // 이 경우 helper를 맨 앞에 다시 세우면 같은 payload가 두 번 처리되므로, "이미 연결됨"으로 본다.
        if existingNotify.map({ CodexNotifyCommand.containsHelper(helperPath, in: $0) }) == true {
            return EditResult(text: text, changed: false, previousNotify: try existingNotify.flatMap(CodexNotifyCommand.previousNotify))
        }

        // notify는 단일 명령 배열이라 새 helper를 단순 추가할 수 없다. 기존 명령은 helper 인자로 직렬화해
        // helper가 payload 저장 후 이어 호출하게 만든다. 이렇게 해야 기존 알림 도구나 플러그인 래퍼를 끊지 않는다.
        let newNotify = CodexNotifyCommand.make(helperPath: helperPath, previousNotify: existingNotify)
        let newLine = "notify = \(try CodexNotifyCommand.encode(newNotify))"

        if let index = topLevelNotifyLineIndex(in: lines) {
            lines[index] = newLine
        } else {
            lines.insert(newLine, at: firstTableIndex(in: lines))
        }

        return EditResult(
            text: lines.joined(separator: "\n"),
            changed: true,
            previousNotify: existingNotify
        )
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func topLevelNotifyLineIndex(in lines: [String]) -> Int? {
        let tableIndex = firstTableIndex(in: lines)
        guard tableIndex > 0 else { return nil }

        // TOML은 table header가 나온 뒤 같은 파일에서 top-level로 되돌아갈 수 없다. 따라서 첫 table 전까지만
        // 전역 notify 후보로 보고, profile/table 내부 notify를 실수로 덮어쓰지 않는다.
        return lines[..<tableIndex].firstIndex(where: isNotifyAssignment)
    }

    private static func firstTableIndex(in lines: [String]) -> Int {
        lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("[") && !trimmed.hasPrefix("#")
        } ?? lines.count
    }

    private static func isNotifyAssignment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed.hasPrefix("notify") else {
            return false
        }

        let suffix = trimmed.dropFirst("notify".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.hasPrefix("=")
    }

    private static func uncommentedValue(_ value: String) -> String {
        var output = ""
        var isInsideString = false
        var isEscaped = false

        for character in value {
            if isEscaped {
                output.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                output.append(character)
                isEscaped = true
                continue
            }

            if character == "\"" {
                output.append(character)
                isInsideString.toggle()
                continue
            }

            if character == "#", !isInsideString {
                break
            }

            output.append(character)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CodexCLIConfigDocumentError: LocalizedError {
    case invalidNotifyValue

    var errorDescription: String? {
        switch self {
        case .invalidNotifyValue:
            "notify 값은 문자열 배열이어야 합니다."
        }
    }
}

public enum CodexNotifyCommand {
    public static let previousNotifyFlag = "--previous-notify"

    public static func make(helperPath: String, previousNotify: [String]?) -> [String] {
        guard let previousNotify, !previousNotify.isEmpty else {
            return [helperPath]
        }

        return [helperPath, previousNotifyFlag, encodeLosslessly(previousNotify)]
    }

    public static func previousNotify(from command: [String]) throws -> [String]? {
        guard let flagIndex = command.firstIndex(of: previousNotifyFlag) else {
            return nil
        }

        let valueIndex = command.index(after: flagIndex)
        guard valueIndex < command.endIndex else {
            throw CodexNotifierHelperInvocationError.missingPreviousNotifyValue
        }

        return try decode(command[valueIndex])
    }

    public static func containsHelper(_ helperPath: String, in command: [String]) -> Bool {
        for argument in command {
            if argument == helperPath {
                return true
            }

            if let nestedCommand = try? decode(argument),
               containsHelper(helperPath, in: nestedCommand) {
                return true
            }
        }

        return false
    }

    public static func encode(_ command: [String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(command)
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ value: String) throws -> [String] {
        let data = Data(value.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }

    private static func encodeLosslessly(_ command: [String]) -> String {
        (try? encode(command)) ?? "[]"
    }
}
