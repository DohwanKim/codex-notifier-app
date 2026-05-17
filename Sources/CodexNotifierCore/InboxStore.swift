import Foundation

public enum CodexNotifierConstants {
    public static let appName = "Codex Notifier"
    public static let bundleIdentifier = "com.dohwankim.codex-notifier"
    public static let payloadCreatedNotification = "com.dohwankim.codex-notifier.payload-created"
    public static let notificationSoundName = "CodexPing.aiff"
}

public struct InboxStore {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(CodexNotifierConstants.appName, isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public var inboxDirectory: URL {
        rootDirectory.appendingPathComponent("inbox", isDirectory: true)
    }

    public var failedDirectory: URL {
        inboxDirectory.appendingPathComponent("failed", isDirectory: true)
    }

    @discardableResult
    public func writePayload(_ data: Data, id: UUID = UUID()) throws -> URL {
        try fileManager.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)

        let fileURL = inboxDirectory.appendingPathComponent("\(id.uuidString).json")
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    public func pendingPayloadFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: inboxDirectory.path) else { return [] }

        return try fileManager
            .contentsOfDirectory(
                at: inboxDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    public func readPayload(at fileURL: URL) throws -> Data {
        try Data(contentsOf: fileURL)
    }

    public func removePayload(at fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    public func moveToFailed(_ fileURL: URL) throws {
        try fileManager.createDirectory(at: failedDirectory, withIntermediateDirectories: true)

        let destination = failedDirectory.appendingPathComponent(fileURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: fileURL, to: destination)
    }
}
