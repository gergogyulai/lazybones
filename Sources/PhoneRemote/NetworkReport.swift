import Foundation
import Network

/// What the phone needs to find Lazybones, for the log: Bonjour is multicast on the local link, so
/// the phone has to share a network segment with one of the Mac's interfaces, and VPNs (Tailscale
/// included) don't carry it. Lists the interfaces it could be found on and which one has the
/// default route, then browses for the advertisement itself to see where it actually shows up,
/// along with any other Apple TVs, which tells whether multicast gets through at all.
@MainActor
final class NetworkReport {
    private let name: String
    private let log: (String) -> Void
    private var browser: NWBrowser?
    private var seen: [String: Set<String>] = [:]
    private var deadline: Task<Void, Never>?

    init(name: String, log: @escaping (String) -> Void) {
        self.name = name
        self.log = log
    }

    func start() {
        let interfaces = Self.interfaces()
        let route = Self.defaultRouteAddress()
        for i in interfaces {
            var notes: [String] = []
            if i.address == route { notes.append("default route") }
            if !i.multicast { notes.append("no multicast: can't advertise here") }
            if i.isVPN { notes.append("VPN: Bonjour doesn't cross it") }
            log("interface \(i.name) \(i.address)/\(i.prefix)\(notes.isEmpty ? "" : " (\(notes.joined(separator: ", ")))")")
        }
        if let route, let i = interfaces.first(where: { $0.address == route }), i.isVPN {
            let lans = interfaces.filter { $0.multicast && !$0.isVPN }.map { "\($0.name) \($0.address)" }
            log("default route is the VPN on \(i.name); the phone must be on the same local network as "
                + (lans.isEmpty ? "one of the Mac's interfaces, and there's none" : lans.joined(separator: " or ")))
        }
        browse()
    }

    func stop() {
        deadline?.cancel()
        browser?.cancel()
        browser = nil
    }

    // MARK: Seeing ourselves

    private func browse() {
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: "_companion-link._tcp", domain: "local."), using: params)
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed(let e), .waiting(let e): self?.log("can't browse Bonjour: \(e)")
                default: break
                }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { r -> (String, Set<String>)? in
                guard case .service(let name, _, _, _) = r.endpoint else { return nil }
                return (name, Set(r.interfaces.map(\.name)))
            }
            Task { @MainActor in self?.update(found) }
        }
        b.start(queue: .main)
        browser = b
        // Long enough for every interface to answer; after that it's just noise.
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func update(_ found: [(String, Set<String>)]) {
        for (name, interfaces) in found {
            let new = interfaces.subtracting(seen[name] ?? [])
            guard !new.isEmpty else { continue }
            seen[name, default: []].formUnion(new)
            let who = name == self.name ? "advertisement visible" : "other device “\(name)”"
            log("\(who) on \(new.sorted().joined(separator: ", "))")
        }
    }

    private func finish() {
        if seen[name] == nil {
            log("couldn't see our own advertisement after 10s: is Local Network access allowed for Lazybones (System Settings > Privacy & Security > Local Network)?")
        }
        let others = seen.keys.filter { $0 != name }
        if others.isEmpty {
            log("no other Apple TVs or Macs answered on this network; multicast may be blocked (guest and dorm networks often isolate devices)")
        }
        stop()
    }

    // MARK: Interfaces

    struct Interface {
        let name: String
        let address: String
        let prefix: Int
        let multicast: Bool
        /// Point-to-point tunnels (utun: Tailscale, WireGuard, iCloud Private Relay) or a CGNAT
        /// address, which is what Tailscale hands out.
        var isVPN: Bool { name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || isCGNAT }
        private var isCGNAT: Bool {
            let parts = address.split(separator: ".").compactMap { Int($0) }
            return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
        }
    }

    static func interfaces() -> [Interface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var out: [Interface] = []
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { String(cString: inet_ntoa($0.pointee.sin_addr)) }
            let mask = ifa.ifa_netmask?.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr } ?? 0
            out.append(Interface(name: String(cString: ifa.ifa_name), address: ip, prefix: mask.nonzeroBitCount,
                                 multicast: flags & IFF_MULTICAST != 0 && flags & IFF_POINTOPOINT == 0))
        }
        return out
    }

    /// The address the phone most likely reaches the Mac at: the default route's, unless that's a
    /// VPN, then Wi-Fi or Ethernet (en*) before anything else, such as a virtual machine's bridge.
    static func lanAddress() -> String? {
        let lans = interfaces().filter { $0.multicast && !$0.isVPN }
        if let route = defaultRouteAddress(), lans.contains(where: { $0.address == route }) { return route }
        return (lans.first { $0.name.hasPrefix("en") } ?? lans.first)?.address
    }

    /// The address traffic to the internet leaves from: a UDP "connect" sends nothing, but makes
    /// the kernel pick the route.
    static func defaultRouteAddress() -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(9).bigEndian
        dest.sin_addr.s_addr = inet_addr("192.0.2.1")
        let connected = withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        guard ok == 0 else { return nil }
        return String(cString: inet_ntoa(local.sin_addr))
    }
}
