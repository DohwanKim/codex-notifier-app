import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "codex-notifier.settings"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> CodexNotifierSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(CodexNotifierSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    public func save(_ settings: CodexNotifierSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

public final class NotificationHistoryStore {
    private let defaults: UserDefaults
    private let historyKey: String
    private let failuresKey: String
    private let maxEntries: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        historyKey: String = "codex-notifier.history",
        failuresKey: String = "codex-notifier.failures",
        maxEntries: Int = 20
    ) {
        self.defaults = defaults
        self.historyKey = historyKey
        self.failuresKey = failuresKey
        self.maxEntries = maxEntries
    }

    public func loadHistory() -> [NotificationHistoryEntry] {
        load([NotificationHistoryEntry].self, key: historyKey)
    }

    public func loadFailures() -> [FailureLogEntry] {
        load([FailureLogEntry].self, key: failuresKey)
    }

    public func appendHistory(_ entry: NotificationHistoryEntry) {
        save([entry] + Array(loadHistory().prefix(maxEntries - 1)), key: historyKey)
    }

    public func appendFailure(_ entry: FailureLogEntry) {
        save([entry] + Array(loadFailures().prefix(maxEntries - 1)), key: failuresKey)
    }

    public func clearFailures(for channel: NotificationChannel) {
        save(loadFailures().filter { $0.channel != channel }, key: failuresKey)
    }

    public func clearFailuresResolvedByHistory() {
        let history = loadHistory()
        let unresolvedFailures = loadFailures().filter { failure in
            !history.contains { entry in
                entry.event.receivedAt >= failure.recordedAt
                    && entry.outcomes.contains { $0.channel == failure.channel && $0.succeeded }
            }
        }
        save(unresolvedFailures, key: failuresKey)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode(T.self, from: data) else {
            if let emptyArray = [] as? T {
                return emptyArray
            }

            fatalError("Unsupported persisted type")
        }

        return decoded
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
