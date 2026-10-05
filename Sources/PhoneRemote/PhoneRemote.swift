import Foundation
import simd

/// The iPhone's Apple TV Remote (Control Center), talking to this Mac as though it were an Apple TV.
///
/// The protocol (Bonjour, PIN pairing, the encrypted Companion link) is corvofeng/atv-core's, built
/// from `Native/AppleTVBridge` into a library that ships inside the app and is loaded at runtime.
/// Without the library the remote reports `.unavailable` and nothing else changes.
@MainActor
public final class PhoneRemote {
    public enum Button: String, Sendable, CaseIterable {
        case up, down, left, right, select, menu, home, siri, mute, power
        case playPause = "play_pause"
        case volumeUp = "volume_up"
        case volumeDown = "volume_down"
    }

    public enum Event: Sendable, Equatable {
        /// A button let go. The phone reports nothing until then, so there are no holds or repeats.
        case button(Button)
        case touchBegan
        /// Finger travel since the last move, in widths of the touch area, y up.
        case touchMoved(SIMD2<Float>)
        case touchEnded
        /// A tap on the touch area.
        case tap
    }

    public enum Status: Sendable, Equatable {
        case off
        /// It couldn't start: no library, no network, ports taken.
        case unavailable(String)
        /// In the phone's list, waiting for it.
        case waiting
        /// A phone is pairing and needs this PIN typed in.
        case pairing(pin: String)
        case connected
    }

    /// Who the phone thinks it's talking to. Made once and kept, or the phone would see a new
    /// Apple TV (and pair again) every launch.
    public struct Identity: Codable, Sendable, Equatable {
        public var name: String
        /// A UUID.
        public var serverID: String
        /// A MAC address, locally administered so it can't clash with real hardware.
        public var deviceID: String

        public init(name: String, serverID: String, deviceID: String) {
            self.name = name
            self.serverID = serverID
            self.deviceID = deviceID
        }

        /// "Lazybones" and four characters that can't be mistaken for one another.
        public static func generate() -> Identity {
            let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
            let suffix = String((0..<4).map { _ in alphabet.randomElement()! })
            var mac = (0..<6).map { _ in UInt8.random(in: 0...255) }
            mac[0] = mac[0] & 0xFC | 0x02
            return Identity(name: "Lazybones \(suffix)",
                            serverID: UUID().uuidString,
                            deviceID: mac.map { String(format: "%02X", $0) }.joined(separator: ":"))
        }
    }

    public var onEvent: ((Event) -> Void)?
    public var onStatusChange: ((Status) -> Void)?
    public var onDiagnostic: ((String) -> Void)?
    /// Log every message the phone sends, not just connections and pairing. Takes effect at the
    /// first start.
    public var verbose = false

    public private(set) var status = Status.off {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    private var handle: UnsafeMutableRawPointer?
    private var relay: Unmanaged<Relay>?
    private var report: NetworkReport?

    public init() {}

    /// Starts answering as `identity`, or restarts if already running, e.g. after the network changed.
    public func start(as identity: Identity) {
        stop()
        let lib: Library
        switch Library.shared {
        case .success(let l): lib = l
        case .failure(let why):
            status = .unavailable(why.message)
            return
        }
        let relay = Unmanaged.passRetained(Relay { [weak self] kind, text, x, y in
            MainActor.assumeIsolated { self?.received(kind, text, x, y) }
        })
        // A new PIN each time: anyone on the network could otherwise pair with a fixed one.
        let pin = UInt32.random(in: 0...9999)
        var error = [CChar](repeating: 0, count: 256)
        let h = lib.start(identity.name, identity.serverID, identity.deviceID, pin, NetworkReport.lanAddress(), verbose, relayCallback,
                          relay.toOpaque(), &error, error.count)
        guard let h else {
            relay.release()
            status = .unavailable(String(cString: error))
            return
        }
        handle = h
        self.relay = relay
        status = .waiting
        onDiagnostic?("answering as “\(identity.name)”")
        // Bonjour only reaches phones on the same local network, so say which that is, and check
        // the advertisement can actually be seen.
        let report = NetworkReport(name: identity.name) { [weak self] in self?.onDiagnostic?($0) }
        report.start()
        self.report = report
    }

    public func stop() {
        report?.stop()
        report = nil
        if let handle, case .success(let lib) = Library.shared { lib.stop(handle) }
        handle = nil
        relay?.release()
        relay = nil
        status = .off
    }

    private func received(_ kind: UInt32, _ text: String, _ x: Double, _ y: Double) {
        guard handle != nil else { return }
        switch kind {
        case 0:
            if let b = Button(rawValue: text) { onEvent?(.button(b)) } else { onDiagnostic?("unrecognized button \(text)") }
        case 1: onEvent?(.touchBegan)
        // The phone's touch area is 1000 units across with y down.
        case 2: onEvent?(.touchMoved(SIMD2(Float(x), Float(-y)) / 1000))
        case 3: onEvent?(.touchEnded)
        case 4: onEvent?(.tap)
        case 5:
            status = .pairing(pin: text)
            onDiagnostic?("pairing")
        case 6:
            status = .waiting
            onDiagnostic?("paired")
        case 7:
            status = .connected
            onDiagnostic?("connected")
        case 9: onDiagnostic?("atv-core: \(text)")
        case 8:
            // Phones also connect briefly just to look; only a remote session leaving changes anything.
            if status == .connected || status.isPairing {
                status = .waiting
                onDiagnostic?("disconnected")
            }
        default: break
        }
    }
}

private extension PhoneRemote.Status {
    var isPairing: Bool { if case .pairing = self { true } else { false } }
}

// MARK: - The library

/// Carries callbacks from the library's threads to the main actor.
private final class Relay: Sendable {
    let deliver: @Sendable (UInt32, String, Double, Double) -> Void
    init(_ deliver: @escaping @Sendable (UInt32, String, Double, Double) -> Void) { self.deliver = deliver }
}

private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafePointer<CChar>?, Double, Double) -> Void

private let relayCallback: Callback = { ctx, kind, text, x, y in
    guard let ctx else { return }
    let relay = Unmanaged<Relay>.fromOpaque(ctx).takeUnretainedValue()
    let text = text.map { String(cString: $0) } ?? ""
    DispatchQueue.main.async { relay.deliver(kind, text, x, y) }
}

/// `liblazybones_atv.dylib`, from the app's Frameworks folder.
private struct Library: @unchecked Sendable {
    typealias Start = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>, UInt32, UnsafePointer<CChar>?, Bool, Callback,
                                      UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>, Int) -> UnsafeMutableRawPointer?
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void

    let start: Start
    let stop: Stop

    struct LoadError: Error { let message: String }

    static let shared: Result<Library, LoadError> = {
        let name = "liblazybones_atv.dylib"
        let candidates = [Bundle.main.privateFrameworksURL, Bundle.main.executableURL?.deletingLastPathComponent()]
            .compactMap { $0?.appendingPathComponent(name).path }
        guard let path = candidates.first(where: FileManager.default.fileExists) else {
            return .failure(LoadError(message: "not built with the Apple TV Remote library (\(name))"))
        }
        guard let handle = dlopen(path, RTLD_NOW) else {
            return .failure(LoadError(message: "couldn't load \(path): \(dlerror().map { String(cString: $0) } ?? "unknown error")"))
        }
        guard let start = dlsym(handle, "lb_atv_start"), let stop = dlsym(handle, "lb_atv_stop") else {
            return .failure(LoadError(message: "\(path) is missing lb_atv_start/lb_atv_stop"))
        }
        return .success(Library(start: unsafeBitCast(start, to: Start.self), stop: unsafeBitCast(stop, to: Stop.self)))
    }()
}
