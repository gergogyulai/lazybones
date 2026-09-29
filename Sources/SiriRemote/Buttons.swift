import Foundation
import IOKit.hid

/// Physical buttons, read as HID consumer-page usages over USB and Bluetooth.
/// Arrows auto-repeat while held; holding selected buttons is reported as its own event.
@MainActor
final class ButtonReader {
    var onEvent: ((RemoteEvent) -> Void)?
    var onUnmapped: ((UInt32) -> Void)?
    var onHeldChanged: ((Bool) -> Void)?
    var onDevicesChanged: (() -> Void)?

    private(set) var exclusive = false
    private(set) var connected = false
    /// The remote's serial number(s); its battery power source is named after it.
    private(set) var serials: Set<String> = []

    private let wantsExclusive: Bool
    private let holdable: Set<RemoteCommand>
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var repeatTimer: Timer?
    /// Running while a holdable button is down; nil once the hold has fired.
    private var holdTimer: Timer?
    // The remote exposes several consumer-page interfaces and can report one press on more than one.
    private var down: Set<UInt32> = []

    /// Consumer-page usages; Generic Desktop system controls are keyed as 0x1_0000 | usage.
    private static let usages: [UInt32: RemoteCommand] = [
        0x42: .up, 0x43: .down, 0x44: .left, 0x45: .right,
        0x80: .select, 0x41: .select,          // clickpad centre reports 0x80 (Selection)
        0x40: .back, 0x224: .back, 0x1_0086: .back, 0x223: .home, 0x60: .home,
        0xCD: .playPause, 0xE9: .volumeUp, 0xEA: .volumeDown, 0xE2: .mute,
        0xCF: .siri, 0x221: .siri, 0x04: .siri, 0x30: .power,
    ]

    init(exclusive: Bool, holdable: Set<RemoteCommand>) {
        wantsExclusive = exclusive
        self.holdable = holdable
    }

    func start() {
        let matches: [[String: Any]] = [
            // Consumer page only. The touch surface belongs to the multitouch driver (see TouchSurface),
            // and seizing its HID interface would starve that driver.
            [kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x0315, kIOHIDPrimaryUsagePageKey: 0x0C],  // USB
            [kIOHIDVendorIDKey: 0x004C, kIOHIDProductIDKey: 0x0315, kIOHIDPrimaryUsagePageKey: 0x0C],  // Bluetooth LE
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            let me = Unmanaged<ButtonReader>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.handle(value) }
        }, ctx)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<ButtonReader>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.refreshDevices() }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<ButtonReader>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.releaseAll(); me.refreshDevices() }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        exclusive = wantsExclusive
            && IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess
        if !exclusive {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        refreshDevices()
    }

    private func refreshDevices() {
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        connected = !devices.isEmpty
        // USB exposes the serial as SerialNumber; Bluetooth LE uses it as the product name.
        serials = Set(devices.flatMap { dev in
            [kIOHIDSerialNumberKey, kIOHIDProductKey].compactMap {
                IOHIDDeviceGetProperty(dev, $0 as CFString) as? String
            }
        })
        onDevicesChanged?()
    }

    private func handle(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(el)
        let usage = IOHIDElementGetUsage(el)
        guard IOHIDValueGetLength(value) <= 4, usage != 0, usage != 0xFFFFFFFF else { return }
        // Buttons are consumer-page usages, except Back, which this remote reports as
        // Generic Desktop "System Menu".
        let key: UInt32
        switch page {
        case 0x0C: key = usage
        case 0x01 where (0x80...0xB7).contains(usage): key = 0x1_0000 | usage  // system controls
        default: return
        }
        let isDown = IOHIDValueGetIntegerValue(value) != 0
        // Only act on up→down and down→up transitions, so duplicate reports collapse into one press.
        if isDown { guard down.insert(key).inserted else { return } }
        else { guard down.remove(key) != nil else { return } }
        onHeldChanged?(!down.isEmpty)

        guard let command = Self.usages[key] else {
            if isDown { onUnmapped?(key) }
            return
        }
        switch command {
        case _ where command.isDirection:
            repeatTimer?.invalidate()
            repeatTimer = nil
            guard isDown else { return }
            emit(command, .press)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.startRepeating(command) }
            }
        case _ where holdable.contains(command):
            if isDown {
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.holdTimer = nil
                        self?.emit(command, .hold)
                    }
                }
            } else if let t = holdTimer {
                // Released before the hold fired: a plain press. After a hold, release does nothing.
                t.invalidate()
                holdTimer = nil
                emit(command, .press)
            }
        default:
            if isDown { emit(command, .press) }
        }
    }

    private func emit(_ command: RemoteCommand, _ source: RemoteEvent.Source) {
        onEvent?(RemoteEvent(command: command, source: source))
    }

    private func startRepeating(_ command: RemoteCommand) {
        var count = 0
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                count += 1
                // Guard against a lost key-up event repeating forever.
                if count > 150 { t.invalidate(); return }
                self?.emit(command, .repeat)
            }
        }
    }

    /// A disconnect can swallow key-ups; don't leave a repeat running or a click suppressing touch.
    private func releaseAll() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        holdTimer?.invalidate()
        holdTimer = nil
        down.removeAll()
        onHeldChanged?(false)
    }
}
