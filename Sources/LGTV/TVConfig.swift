import Foundation

/// A paired TV, saved by the client. The client key is what the TV hands out after its on-screen prompt.
public struct TVConfig: Codable, Equatable, Sendable {
    public var name: String
    public var host: String
    public var clientKey: String?

    public init(name: String, host: String, clientKey: String? = nil) {
        self.name = name
        self.host = host
        self.clientKey = clientKey
    }
}
