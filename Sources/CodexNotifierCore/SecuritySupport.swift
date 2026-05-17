import Foundation
import Security

public struct SecretRedactor: Sendable {
    private let secrets: [String]

    public init(secrets: [String]) {
        self.secrets = secrets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    public func redact(_ text: String) -> String {
        secrets.reduce(text) { partial, secret in
            partial.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
    }
}

public enum SecretKey: String, CaseIterable, Sendable {
    case telegramBotToken = "TELEGRAM_BOT_TOKEN"
    case telegramChatID = "TELEGRAM_CHAT_ID"
    case teamsWebhookURL = "TEAMS_WEBHOOK_URL"
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

public final class KeychainSecretStore {
    private let service: String

    public init(service: String = CodexNotifierConstants.bundleIdentifier) {
        self.service = service
    }

    public func read(_ key: SecretKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String, for key: SecretKey) throws {
        if value.isEmpty {
            try delete(key)
            return
        }

        let data = Data(value.utf8)
        let existing = try read(key)

        if existing == nil {
            var query = baseQuery(for: key)
            query[kSecValueData as String] = data

            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        } else {
            let status = SecItemUpdate(
                baseQuery(for: key) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }

    public func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
