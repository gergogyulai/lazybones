import AppKit
import ObjectiveC

/// The built-in keyboard's backlight on MacBooks, through CoreBrightness's private
/// `KeyboardBrightnessClient`, the class Control Center's keyboard brightness slider uses. There's no
/// public API for it. On Macs without a backlit keyboard, or if a macOS update renames things,
/// `isAvailable` is false and everything else does nothing.
///
/// `hold(_:)` takes over the backlight and remembers how it was; `release()` puts it back. Auto
/// brightness is turned off while held, or the ambient light sensor would undo the level.
@MainActor
public final class KeyboardBacklight {
    private typealias Brightness = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Query = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias SetBrightness = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
    private typealias SetAuto = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool

    private let client: NSObject?
    private let id: UInt64

    /// How it was before `hold`, or nil while not held.
    private var saved: (brightness: Float, auto: Bool)?
    private var held: Double?
    private var observers: [NSObjectProtocol] = []

    public var isAvailable: Bool { client != nil }

    public init() {
        (client, id) = Self.connect() ?? (nil, 0)
        guard client != nil else { return }
        // Waking can bring the backlight back up.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, let level = self.held { self.write(level) } }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        })
    }

    /// Sets the backlight to `level` (0 is off, 1 is full) until `release()`.
    public func hold(_ level: Double) {
        guard client != nil else { return }
        if saved == nil {
            saved = (brightness(), isAutoOn())
            setAuto(false)
        }
        held = min(max(level, 0), 1)
        write(held!)
    }

    /// Back to the brightness and auto brightness it had before `hold`.
    public func release() {
        guard let s = saved else { return }
        saved = nil
        held = nil
        write(Double(s.brightness))
        if s.auto { setAuto(true) }
    }

    // MARK: CoreBrightness

    private static func connect() -> (NSObject, UInt64)? {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = type.init()
        let copyIDs = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: copyIDs),
              let ids = client.perform(copyIDs)?.takeRetainedValue() as? [NSNumber] else { return nil }
        let builtIn = NSSelectorFromString("isKeyboardBuiltIn:")
        guard client.responds(to: builtIn) else { return nil }
        let isBuiltIn = unsafeBitCast(client.method(for: builtIn), to: Query.self)
        guard let id = ids.map(\.uint64Value).first(where: { isBuiltIn(client, builtIn, $0) }) else { return nil }
        return (client, id)
    }

    private func call<F>(_ name: String, as: F.Type) -> F? {
        let sel = NSSelectorFromString(name)
        guard let client, client.responds(to: sel) else { return nil }
        return unsafeBitCast(client.method(for: sel), to: F.self)
    }

    private func brightness() -> Float {
        guard let client, let f = call("brightnessForKeyboard:", as: Brightness.self) else { return 0 }
        return f(client, NSSelectorFromString("brightnessForKeyboard:"), id)
    }

    private func isAutoOn() -> Bool {
        guard let client, let f = call("isAutoBrightnessEnabledForKeyboard:", as: Query.self) else { return false }
        return f(client, NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:"), id)
    }

    /// Fades to `level` without saving it as the user's own setting.
    private func write(_ level: Double) {
        guard let client, let f = call("setBrightness:fadeSpeed:commit:forKeyboard:", as: SetBrightness.self) else { return }
        _ = f(client, NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:"), Float(level), 500, false, id)
    }

    private func setAuto(_ on: Bool) {
        guard let client, let f = call("enableAutoBrightness:forKeyboard:", as: SetAuto.self) else { return }
        _ = f(client, NSSelectorFromString("enableAutoBrightness:forKeyboard:"), on, id)
    }
}
