import Foundation

/// A semantic command from the remote, whatever produced it (click, auto-repeat, hold or swipe).
public enum RemoteCommand: String, Sendable, CaseIterable {
    case up, down, left, right, select, back, home
    case playPause, volumeUp, volumeDown, mute, siri, power

    public var isDirection: Bool { [.up, .down, .left, .right].contains(self) }
}

public struct RemoteEvent: Sendable, Equatable {
    public enum Source: String, Sendable {
        case press    // a button went down (holdable buttons fire on release, once known not to be a hold)
        case `repeat` // a held direction auto-repeating
        case hold     // a holdable button held for 0.7s; fires while still held
        case swipe    // touch surface
    }

    public let command: RemoteCommand
    public let source: Source

    public init(command: RemoteCommand, source: Source) {
        self.command = command
        self.source = source
    }
}

/// The Siri Remote (USB-C, 2022), over USB or Bluetooth.
///
/// Everything device-specific lives in this module: HID button usages and their duplicate reports,
/// auto-repeat, hold detection, the touch surface (which macOS routes to its multitouch driver,
/// not HID) and battery state. Clients get `RemoteEvent`s and a `Status`, nothing lower level.
@MainActor
public final class SiriRemote {
    public struct Options: Sendable {
        /// Take the buttons away from macOS, so e.g. volume keys don't also change system volume.
        /// When exclusive, the client is responsible for acting on volume and mute.
        public var exclusive = true
        /// Buttons whose 0.7s hold is reported as `(command, .hold)` instead of a press. Their press
        /// then fires on release, once it's known not to be a hold, so keep this to buttons that need it.
        public var holdable: Set<RemoteCommand> = [.home]
        /// Touch travel per focus move while dragging, as a fraction of the surface (0...1).
        public var swipeStep: Float = 0.30

        public init() {}
    }

    public struct Battery: Sendable, Equatable {
        public let percent: Int
        public let charging: Bool
        public let pluggedIn: Bool
    }

    public struct Status: Sendable, Equatable {
        public enum Buttons: Sendable, Equatable {
            case disconnected
            case shared     // connected, but macOS also acts on the buttons
            case exclusive  // connected and seized
        }

        public var buttons: Buttons = .disconnected
        public var touch = false
        public var battery: Battery?

        public init() {}
    }

    public var onEvent: ((RemoteEvent) -> Void)?
    /// Where a finger resting on the touch surface sits relative to where focus last moved, in
    /// steps (-1...1 on each axis, x right and y up), or nil when it lifts or clicks. tvOS tilts
    /// the focused item by this, so it seems to move under your thumb.
    public var onTouchRest: ((SIMD2<Float>?) -> Void)?
    public var onStatusChange: ((Status) -> Void)?
    /// Human-readable notes for debugging, e.g. a button this module doesn't recognize yet.
    public var onDiagnostic: ((String) -> Void)?

    public private(set) var status = Status() {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    private let buttons: ButtonReader
    private let touch: TouchSurface
    private let battery = BatteryMonitor()
    private var started = false
    private var ready = false  // hold status updates until every part has started

    public init(options: Options = Options()) {
        buttons = ButtonReader(exclusive: options.exclusive, holdable: options.holdable)
        touch = TouchSurface(step: options.swipeStep)
    }

    public func start() {
        guard !started else { return }
        started = true

        buttons.onEvent = { [weak self] in self?.onEvent?($0) }
        buttons.onUnmapped = { [weak self] usage in
            self?.onDiagnostic?(String(format: "unrecognized button usage %02X:%02X", usage >> 16 == 0 ? 0x0C : usage >> 16, usage & 0xFFFF))
        }
        // A click rests a finger on the surface; don't let it also count as a swipe.
        buttons.onHeldChanged = { [weak self] held in self?.touch.suppressed = held }
        buttons.onDevicesChanged = { [weak self] in self?.refreshStatus() }
        touch.onSwipe = { [weak self] in self?.onEvent?(RemoteEvent(command: $0, source: .swipe)) }
        touch.onRest = { [weak self] in self?.onTouchRest?($0) }
        touch.onConnectedChanged = { [weak self] in self?.refreshStatus() }
        battery.onChange = { [weak self] in self?.refreshStatus() }

        touch.start()
        buttons.start()
        battery.start()
        ready = true
        refreshStatus()
    }

    private func refreshStatus() {
        guard ready else { return }
        var s = Status()
        s.buttons = !buttons.connected ? .disconnected : buttons.exclusive ? .exclusive : .shared
        s.touch = touch.connected
        s.battery = battery.reading(for: buttons.serials)
        status = s
    }
}
