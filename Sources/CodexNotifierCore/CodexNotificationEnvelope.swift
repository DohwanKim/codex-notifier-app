import Foundation

public struct CodexNotificationEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let codexNotifierEnvelopeVersion: Int
    public let payload: JSONValue
    public let focusTarget: MacOSFocusTarget?

    public init(
        payload: JSONValue,
        focusTarget: MacOSFocusTarget?,
        codexNotifierEnvelopeVersion: Int = CodexNotificationEnvelope.currentVersion
    ) {
        self.codexNotifierEnvelopeVersion = codexNotifierEnvelopeVersion
        self.payload = payload
        self.focusTarget = focusTarget
    }

    public static func decode(from data: Data) throws -> CodexNotificationEnvelope {
        if let envelope = try? JSONDecoder().decode(CodexNotificationEnvelope.self, from: data),
           envelope.codexNotifierEnvelopeVersion == currentVersion {
            return envelope
        }

        return CodexNotificationEnvelope(
            payload: try CodexPayloadParser.parse(data),
            focusTarget: nil
        )
    }
}
