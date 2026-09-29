// RemoteHUD — floating window showing live Apple TV remote HID inputs.
// Build: swiftc -O -parse-as-library RemoteHUD.swift -o RemoteHUD

import SwiftUI
import IOKit.hid
import IOKit.ps

// MARK: - HID

struct Key: Hashable { let page: UInt32; let usage: UInt32 }

struct Event: Identifiable {
    let id = UUID()
    let time: Date
    let key: Key
    let value: String
    let pressed: Bool
    let source: String
}

let knownNames: [Key: String] = [
    Key(page: 0x0C, usage: 0x30): "Power",
    Key(page: 0x0C, usage: 0x40): "Menu",
    Key(page: 0x0C, usage: 0x41): "Select",
    Key(page: 0x0C, usage: 0x42): "Up",
    Key(page: 0x0C, usage: 0x43): "Down",
    Key(page: 0x0C, usage: 0x44): "Left",
    Key(page: 0x0C, usage: 0x45): "Right",
    Key(page: 0x0C, usage: 0x60): "TV",
    Key(page: 0x0C, usage: 0x04): "Mic",
    Key(page: 0x0C, usage: 0xCD): "Play/Pause",
    Key(page: 0x0C, usage: 0xCF): "Siri",
    Key(page: 0x0C, usage: 0xE2): "Mute",
    Key(page: 0x0C, usage: 0xE9): "Vol +",
    Key(page: 0x0C, usage: 0xEA): "Vol −",
    Key(page: 0x0C, usage: 0x221): "Search",
    Key(page: 0x0C, usage: 0x223): "Home",
    Key(page: 0x0C, usage: 0x224): "Back",
]

func name(for key: Key) -> String {
    knownNames[key] ?? String(format: "%02X:%02X", key.page, key.usage)
}

// The public IOPSCopyPowerSourcesInfo() only lists internal batteries. Accessories (AirPods, the remote)
// come from IOPSCopyPowerSourcesByType(kIOPSSourceAll = 0), which is exported but not in the SDK headers.
private let copyPowerSourcesByType: (@convention(c) (Int32) -> Unmanaged<CFTypeRef>?)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPSCopyPowerSourcesByType") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (Int32) -> Unmanaged<CFTypeRef>?).self)
}()

func copyAllPowerSources() -> CFTypeRef? {
    copyPowerSourcesByType?(0)?.takeRetainedValue() ?? IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
}

@MainActor
final class RemoteMonitor: ObservableObject {
    @Published var held: [Key: Date] = [:]          // buttons currently down
    @Published var log: [Event] = []                // recent events, newest first
    @Published var connected: [String] = []
    @Published var lastPulse: [Key: Date] = [:]     // brief highlight for one-shot/relative inputs
    @Published var battery: Battery?

    struct Battery { let percent: Int; let charging: Bool; let onPower: Bool }

    private var serials: Set<String> = []           // remote's serial; its power source is named after it

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let echo = CommandLine.arguments.contains("--log")

    init() {
        // Siri Remote (USB-C): Apple USB vendor 0x05AC, and Apple Bluetooth vendor 0x004C over BLE.
        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x0315],
            [kIOHIDVendorIDKey: 0x004C, kIOHIDProductIDKey: 0x0315],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            let me = Unmanaged<RemoteMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.handle(value) }
        }, ctx)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<RemoteMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.refreshDevices() }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<RemoteMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.held.removeAll(); me.refreshDevices() }
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let rc = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if rc != kIOReturnSuccess {
            connected = ["open failed (0x\(String(rc, radix: 16))) — grant Input Monitoring"]
        }

        // Battery: the remote shows up as an IOPowerSource. Listen for changes, plus a slow poll as backup.
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            let me = Unmanaged<RemoteMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.refreshBattery() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBattery() }
        }
    }

    private func refreshBattery() {
        guard let info = copyAllPowerSources(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let n = d[kIOPSNameKey] as? String, serials.contains(n) else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            battery = Battery(percent: max > 0 ? cur * 100 / max : cur,
                              charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                              onPower: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
            return
        }
        battery = nil
    }

    private func refreshDevices() {
        let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        // USB exposes the serial as SerialNumber; BLE uses it as the Product name.
        serials = Set(set.flatMap { dev in
            [kIOHIDSerialNumberKey, kIOHIDProductKey].compactMap {
                IOHIDDeviceGetProperty(dev, $0 as CFString) as? String
            }
        })
        refreshBattery()
        connected = set.map { dev in
            let t = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? "?"
            return t == "USB" ? "USB" : "Bluetooth"
        }
        .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        .map { "Siri Remote · \($0.key) (\($0.value) interfaces)" }
        .sorted()
    }

    private func handle(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let dev = IOHIDElementGetDevice(el)
        let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        guard pid == 0x0315 else { return }
        let transport = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? "?"
        let source = transport == "USB" ? "USB" : "BT"
        let key = Key(page: IOHIDElementGetUsagePage(el), usage: IOHIDElementGetUsage(el))
        // Skip array-index placeholders and "no event" usages.
        if key.usage == 0 || key.usage == 0xFFFFFFFF { return }

        let len = IOHIDValueGetLength(value)
        let now = Date()
        let text: String
        var pressed = false

        if len > 4 {
            // Vendor blob (e.g. touch surface data) — show as hex.
            let bytes = UnsafeBufferPointer(start: IOHIDValueGetBytePtr(value), count: len)
            if bytes.allSatisfy({ $0 == 0 }) { return }
            text = bytes.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
                + (len > 16 ? " …" : "")
            lastPulse[key] = now
        } else {
            let v = IOHIDValueGetIntegerValue(value)
            text = "\(v)"
            if IOHIDElementIsRelative(el) {
                if v == 0 { return }
                lastPulse[key] = now
            } else if IOHIDElementGetLogicalMax(el) <= 1 || knownNames[key] != nil {
                // Button-like
                pressed = v != 0
                if pressed { held[key] = held[key] ?? now } else { held[key] = nil }
            } else {
                lastPulse[key] = now
            }
        }

        log.insert(Event(time: now, key: key, value: text, pressed: pressed, source: source), at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }

        if echo {
            print(String(format: "%@  %@  page=%02X usage=%02X  %@  %@",
                         now.formatted(.dateTime.hour().minute().second()), source,
                         key.page, key.usage, name(for: key), text))
            fflush(stdout)
        }
    }
}

// MARK: - UI

struct Chip: View {
    let label: String
    let active: Bool
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(active ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(active ? Color.white : Color.secondary)
            .animation(.easeOut(duration: 0.08), value: active)
    }
}

struct BatteryRow: View {
    let battery: RemoteMonitor.Battery?
    var body: some View {
        HStack(spacing: 6) {
            Text("BATTERY").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            if let b = battery {
                Image(systemName: symbol(b))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(b.percent <= 20 && !b.charging ? .red : b.charging ? .green : .primary)
                Text("\(b.percent)%").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(b.charging ? "charging" : b.onPower ? "plugged in" : "on battery")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("unknown").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
    private func symbol(_ b: RemoteMonitor.Battery) -> String {
        if b.charging { return "battery.100percent.bolt" }
        switch b.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct ContentView: View {
    @StateObject private var hid = RemoteMonitor()
    private let layout: [[Key]] = [
        [0x40, 0x223, 0x221, 0xCF, 0x30].map { Key(page: 0x0C, usage: $0) },
        [0x42, 0x43, 0x44, 0x45, 0x41].map { Key(page: 0x0C, usage: $0) },
        [0xCD, 0xE9, 0xEA, 0xE2].map { Key(page: 0x0C, usage: $0) },
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                BatteryRow(battery: hid.battery)

                // Held right now, including anything not in the fixed layout.
                HStack(spacing: 6) {
                    Text("HELD").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    if hid.held.isEmpty && !recentPulse(ctx.date) {
                        Text("—").foregroundStyle(.tertiary)
                    }
                    ForEach(hid.held.keys.sorted { $0.usage < $1.usage }, id: \.self) { k in
                        Chip(label: name(for: k), active: true)
                    }
                    ForEach(pulsing(ctx.date), id: \.self) { k in
                        Chip(label: name(for: k), active: true).opacity(0.6)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 24)

                ForEach(layout.indices, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(layout[r], id: \.self) { k in
                            Chip(label: name(for: k), active: hid.held[k] != nil)
                        }
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(hid.log.prefix(12)) { e in
                            HStack(spacing: 8) {
                                Text(e.time.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(2))))
                                    .foregroundStyle(.tertiary)
                                Text(e.source).foregroundStyle(.tertiary).frame(width: 26, alignment: .leading)
                                Text(name(for: e.key)).frame(width: 80, alignment: .leading)
                                Text(e.value).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 170)

                Text(hid.connected.isEmpty ? "no remote found" : hid.connected.joined(separator: "\n"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 380)
    }

    private func pulsing(_ now: Date) -> [Key] {
        hid.lastPulse.filter { now.timeIntervalSince($0.value) < 0.25 && hid.held[$0.key] == nil }
            .keys.sorted { $0.usage < $1.usage }
    }
    private func recentPulse(_ now: Date) -> Bool { !pulsing(now).isEmpty }
}

@main
struct RemoteHUDApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("Remote HUD", id: "hud") {
            ContentView()
                .background(.regularMaterial)
        }
        .windowLevel(.floating)
        .windowResizability(.contentSize)
    }
}
