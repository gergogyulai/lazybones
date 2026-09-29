import Foundation

/// The touch surface, read through MultitouchSupport (private framework): the remote registers as a
/// multitouch device, so touches never show up as HID reports.
///
/// Swipes behave like tvOS: a flick moves focus one step, a long drag keeps stepping as the finger
/// travels, and can change direction mid-drag.
@MainActor
final class TouchSurface {
    var onSwipe: ((RemoteCommand) -> Void)?
    var onConnectedChanged: (() -> Void)?
    /// Set while a physical button is held; a click shouldn't also register as a swipe.
    var suppressed = false {
        didSet { if suppressed { active?.spent = true } }
    }
    private(set) var connected = false {
        didSet { if connected != oldValue { onConnectedChanged?() } }
    }

    // Normalized units: the surface is 0...1 on both axes, y grows upward.
    private let step: Float
    private let flickDistance: Float = 0.10
    private let flickTime = 0.45

    private struct Touch {
        var anchor: (x: Float, y: Float)
        var start: (x: Float, y: Float)
        var last: (x: Float, y: Float)
        var began: TimeInterval
        var emitted = false
        var spent = false  // a click happened during this touch; ignore it
    }
    private var active: Touch?
    private var device: MT.Device?
    private var watchdog: Timer?

    init(step: Float) {
        self.step = step
    }

    func start() {
        guard MT.available else { return }
        touchSink = { [weak self] frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(frame) } }
        }
        reconnectIfNeeded()
        // The remote can connect after launch, or come back as a new device after sleep or re-pairing.
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnectIfNeeded() }
        }
    }

    private func reconnectIfNeeded() {
        guard let found = MT.findRemote() else {
            device = nil
            active = nil
            connected = false
            return
        }
        if let device, device.id == found.id, MT.isRunning(device) {
            found.release()
            return
        }
        device?.release()
        MT.startReceiving(from: found)
        device = found
        connected = true
    }

    private func handle(_ frame: TouchFrame) {
        guard let p = frame.point else {
            if let t = active { finish(t, at: frame.time) }
            active = nil
            return
        }
        guard var t = active else {
            active = Touch(anchor: p, start: p, last: p, began: frame.time, spent: suppressed)
            return
        }
        defer { active = t }
        t.last = p
        if t.spent { return }

        let dx = p.x - t.anchor.x, dy = p.y - t.anchor.y
        if max(abs(dx), abs(dy)) >= step {
            onSwipe?(direction(dx, dy))
            t.anchor = p
            t.emitted = true
        }
    }

    private func finish(_ t: Touch, at time: TimeInterval) {
        guard !t.spent, !t.emitted, time - t.began <= flickTime else { return }
        let dx = t.last.x - t.start.x, dy = t.last.y - t.start.y
        if max(abs(dx), abs(dy)) >= flickDistance { onSwipe?(direction(dx, dy)) }
    }

    private func direction(_ dx: Float, _ dy: Float) -> RemoteCommand {
        abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
    }
}

// MARK: - MultitouchSupport bindings

struct TouchFrame: Sendable {
    let time: TimeInterval
    let x: Float, y: Float
    let touching: Bool
    var point: (x: Float, y: Float)? { touching ? (x, y) : nil }
}

private struct MTPoint { var x: Float; var y: Float }
private struct MTReadout { var pos: MTPoint; var vel: MTPoint }
/// 96-byte contact record, layout as reverse-engineered by the trackpad-tools community.
private struct MTFinger {
    var frame: Int32; var timestamp: Double
    var identifier: Int32; var state: Int32; var fingerID: Int32; var handID: Int32
    var normalized: MTReadout
    var size: Float; var zero1: Int32
    var angle: Float; var majorAxis: Float; var minorAxis: Float
    var mm: MTReadout
    var zero2: (Int32, Int32); var unk2: Float
}

private typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

nonisolated(unsafe) private var touchSink: ((TouchFrame) -> Void)?

/// Runs on MultitouchSupport's thread. States 3–5 are make-touch/touching/break-touch; 1–2 are
/// hover and 6–7 lift-off, which report drifting positions and are ignored.
private let contactCallback: MTContactCallback = { _, fingers, count, timestamp, _ in
    var frame = TouchFrame(time: timestamp, x: 0, y: 0, touching: false)
    if let fingers, count > 0 {
        let f = fingers.load(as: MTFinger.self)
        if (3...5).contains(f.state) {
            frame = TouchFrame(time: timestamp, x: f.normalized.pos.x, y: f.normalized.pos.y, touching: true)
        }
    }
    touchSink?(frame)
    return 0
}

private enum MT {
    /// A retained MTDevice. Device lists hand out new objects on every call, so identity is the ID.
    struct Device {
        let ref: UnsafeMutableRawPointer
        let id: UInt64
        func release() { Unmanaged<AnyObject>.fromOpaque(ref).release() }
    }

    static let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    static var available: Bool { handle != nil }

    private static func sym<T>(_ name: String) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static let createList: (@convention(c) () -> Unmanaged<CFArray>)? = sym("MTDeviceCreateList")
    private static let registerCallback: (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void)? = sym("MTRegisterContactFrameCallback")
    private static let startDevice: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void)? = sym("MTDeviceStart")
    private static let running: (@convention(c) (UnsafeMutableRawPointer) -> Bool)? = sym("MTDeviceIsRunning")
    private static let familyID: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32)? = sym("MTDeviceGetFamilyID")
    private static let deviceID: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32)? = sym("MTDeviceGetDeviceID")
    private static let isBuiltIn: (@convention(c) (UnsafeMutableRawPointer) -> Bool)? = sym("MTDeviceIsBuiltIn")

    /// The Siri Remote reports multitouch family 145; built-in and Magic Trackpads are skipped.
    /// The returned device is retained; call `release()` when done with it.
    static func findRemote() -> Device? {
        guard let list = createList?().takeRetainedValue() as? [AnyObject] else { return nil }
        for obj in list {
            let ref = Unmanaged.passUnretained(obj).toOpaque()
            var family: Int32 = 0
            _ = familyID?(ref, &family)
            guard family == 145, isBuiltIn?(ref) == false else { continue }
            var id: UInt64 = 0
            _ = deviceID?(ref, &id)
            _ = Unmanaged.passRetained(obj)
            return Device(ref: ref, id: id)
        }
        return nil
    }

    static func startReceiving(from device: Device) {
        registerCallback?(device.ref, contactCallback)
        startDevice?(device.ref, 0)
    }

    static func isRunning(_ device: Device) -> Bool { running?(device.ref) ?? true }
}
