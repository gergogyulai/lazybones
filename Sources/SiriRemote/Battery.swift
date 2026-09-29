import Foundation
import IOKit.ps

/// The remote's battery, from the power source macOS publishes for it (named after its serial number).
@MainActor
final class BatteryMonitor {
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            let me = Unmanaged<BatteryMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.onChange?() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            runLoopSource = src
        }
        // Accessory levels don't always trigger the notification; poll slowly as a backup.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    func reading(for serials: Set<String>) -> SiriRemote.Battery? {
        guard !serials.isEmpty, let info = copyAllPowerSources(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let name = d[kIOPSNameKey] as? String, serials.contains(name) else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return SiriRemote.Battery(
                percent: max > 0 ? current * 100 / max : current,
                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                pluggedIn: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            )
        }
        return nil
    }
}

// The public IOPSCopyPowerSourcesInfo() only lists internal batteries. Accessories come from
// IOPSCopyPowerSourcesByType(kIOPSSourceAll = 0), which is exported but not in the SDK headers.
private let copyPowerSourcesByType: (@convention(c) (Int32) -> Unmanaged<CFTypeRef>?)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPSCopyPowerSourcesByType") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (Int32) -> Unmanaged<CFTypeRef>?).self)
}()

private func copyAllPowerSources() -> CFTypeRef? {
    copyPowerSourcesByType?(0)?.takeRetainedValue() ?? IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
}
