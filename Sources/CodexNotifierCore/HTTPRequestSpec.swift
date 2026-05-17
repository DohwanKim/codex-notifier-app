import Foundation

public struct HTTPRequestSpec: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data

    public init(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    public var jsonBody: [String: JSONValue]? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: body),
              case let .object(object) = value else {
            return nil
        }

        return object
    }
}

public enum RequestBuilderError: Error, Equatable {
    case invalidURL
    case invalidJSONBody
}
