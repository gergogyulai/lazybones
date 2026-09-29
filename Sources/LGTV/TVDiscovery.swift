import Foundation
import Network

/// A TV found on the network, not yet resolved to an address.
public struct FoundTV: Identifiable, Hashable, Sendable {
    public let name: String
    let endpoint: NWEndpoint
    public var id: String { name }
}

/// Finds LG webOS TVs with Bonjour (they advertise AirPlay) and resolves them to addresses.
@MainActor
public final class TVDiscovery: ObservableObject {
    @Published public private(set) var found: [FoundTV] = []

    private var browser: NWBrowser?

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let tvs = results.compactMap { r -> FoundTV? in
                guard case let .service(name, _, _, _) = r.endpoint else { return nil }
                var manufacturer = ""
                if case let .bonjour(txt) = r.metadata { manufacturer = txt["manufacturer"] ?? "" }
                guard name.hasPrefix("LG") || manufacturer.localizedCaseInsensitiveContains("LG") else { return nil }
                return FoundTV(name: name, endpoint: r.endpoint)
            }
            DispatchQueue.main.async {
                self?.found = tvs.sorted { $0.name < $1.name }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Resolves a found TV to an IPv4 address by briefly connecting to its advertised service.
    public static func resolve(_ tv: FoundTV) async -> String? {
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let conn = NWConnection(to: tv.endpoint, using: params)
        return await withCheckedContinuation { cont in
            var done = false
            let finish: (String?) -> Void = { host in
                guard !done else { return }
                done = true
                conn.cancel()
                cont.resume(returning: host)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _) = conn.currentPath?.remoteEndpoint {
                        finish("\(host)".components(separatedBy: "%").first)
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            conn.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(nil) }
        }
    }
}
