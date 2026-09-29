import CoreAudio
import CoreWLAN
import Foundation
import Network

/// Output devices from CoreAudio. Web views play through the system default output,
/// so switching the default is how Lull's audio gets routed.
enum AudioOutputs {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let transport: UInt32

        /// HDMI or DisplayPort: audio going to a TV or monitor.
        var isDisplay: Bool {
            transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
        }

        var symbol: String {
            if name.localizedCaseInsensitiveContains("airpods") { return "airpods" }
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            case kAudioDeviceTransportTypeUSB: return "cable.connector"
            case kAudioDeviceTransportTypeBuiltIn: return "hifispeaker.fill"
            default: return "speaker.wave.2.fill"
            }
        }
    }

    static func all() -> [Device] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0,
                  get(id, kAudioDevicePropertyIsHidden, as: UInt32.self) != 1,
                  let name = name(of: id) else { return nil }
            return Device(id: id, name: name, transport: get(id, kAudioDevicePropertyTransportType, as: UInt32.self) ?? 0)
        }
    }

    static func defaultID() -> AudioDeviceID? {
        get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioDeviceID.self)
    }

    static func setDefault(_ id: AudioDeviceID) {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func get<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, as _: T.Type) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

struct NetworkInfo: Equatable {
    enum Kind { case wifi, ethernet, other, offline }

    var kind = Kind.offline
    var interface: String?
    var address: String?
    /// Only readable with Location Services permission; usually nil.
    var ssid: String?
    var rssi: Int?
    var vpn = false

    var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }

    var title: String {
        switch kind {
        case .wifi: ssid ?? "Wi-Fi"
        case .ethernet: "Ethernet"
        case .other: "Network"
        case .offline: "Not Connected"
        }
    }

    /// 0–3 bars from RSSI, like the menu bar.
    var bars: Int? {
        guard kind == .wifi, let rssi, rssi != 0 else { return nil }
        return rssi >= -55 ? 3 : rssi >= -67 ? 2 : rssi >= -78 ? 1 : 0
    }
}

/// Keeps a NetworkInfo current from NWPathMonitor.
@MainActor
final class NetworkMonitor {
    var onChange: ((NetworkInfo) -> Void)?
    private let monitor = NWPathMonitor()

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let info = Self.info(for: path)
            DispatchQueue.main.async { self?.onChange?(info) }
        }
        monitor.start(queue: DispatchQueue(label: "lull.network"))
    }

    /// Re-reads Wi-Fi details, which NWPathMonitor doesn't report changes for.
    func refresh() {
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
