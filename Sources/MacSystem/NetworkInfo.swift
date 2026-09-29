import CoreWLAN
import Foundation
import Network

public struct NetworkInfo: Equatable, Sendable {
    public enum Kind: Sendable { case wifi, ethernet, other, offline }

    public var kind = Kind.offline
    public var interface: String?
    public var address: String?
    /// Only readable with Location Services permission; usually nil.
    public var ssid: String?
    public var rssi: Int?
    public var vpn = false

    public init() {}

    public var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }

    public var title: String {
        switch kind {
        case .wifi: ssid ?? "Wi-Fi"
        case .ethernet: "Ethernet"
        case .other: "Network"
        case .offline: "Not Connected"
        }
    }

    /// 0–3 bars from RSSI, like the menu bar.
    public var bars: Int? {
        guard kind == .wifi, let rssi, rssi != 0 else { return nil }
        return rssi >= -55 ? 3 : rssi >= -67 ? 2 : rssi >= -78 ? 1 : 0
    }
}

/// Keeps a NetworkInfo current from NWPathMonitor.
@MainActor
public final class NetworkMonitor {
    public var onChange: ((NetworkInfo) -> Void)?
    private let monitor = NWPathMonitor()

    public init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let info = Self.info(for: path)
            DispatchQueue.main.async { self?.onChange?(info) }
        }
        monitor.start(queue: DispatchQueue(label: "lull.network"))
    }

    /// Re-reads Wi-Fi details, which NWPathMonitor doesn't report changes for.
    public func refresh() {
        onChange?(Self.info(for: monitor.currentPath))
    }

    nonisolated private static func info(for path: NWPath) -> NetworkInfo {
        var info = NetworkInfo()
        guard path.status == .satisfied, let first = path.availableInterfaces.first else { return info }
        // With a VPN up, the tunnel comes first; describe the physical link underneath it.
        let iface = path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet } ?? first
        info.vpn = first.type == .other && ["utun", "ipsec", "ppp"].contains { first.name.hasPrefix($0) }
        info.interface = iface.name
        info.address = ipv4(iface.name)
        switch iface.type {
        case .wifi:
            info.kind = .wifi
            let wifi = CWWiFiClient.shared().interface(withName: iface.name)
            info.ssid = wifi?.ssid()
            info.rssi = wifi?.rssiValue()
        case .wiredEthernet: info.kind = .ethernet
        default: info.kind = .other
        }
        return info
    }

    nonisolated private static func ipv4(_ name: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var p = list
        while let a = p?.pointee {
            defer { p = a.ifa_next }
            guard String(cString: a.ifa_name) == name, let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }
}
